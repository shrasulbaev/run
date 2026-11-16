"""ADAM RUN API. Fixed OTP is explicit demo functionality, never production auth."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256
import hmac
import secrets
import uuid
from typing import Literal

import jwt
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator, TypeAdapter
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import Boolean, DateTime, Integer, String, create_engine, func, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    app_env: Literal['development', 'test', 'demo', 'production'] = 'development'
    test_auth_enabled: bool = True
    database_url: str = 'sqlite:///./adam_run.db'
    jwt_secret: str = 'local-development-only-change-before-sharing'
    cors_origins: list[str] = ['http://localhost:7357', 'http://127.0.0.1:7357']

    def runtime_database_url(self):
        if self.app_env == 'production' and self.test_auth_enabled:
            raise RuntimeError('Fixed test OTP is forbidden in production')
        if self.app_env in {'demo', 'production'} and (
            len(self.jwt_secret) < 32 or self.jwt_secret.startswith('local-')
        ):
            raise RuntimeError('Configure a strong JWT_SECRET for hosted environments')
        url = make_url(self.database_url)
        if url.drivername in {'postgres', 'postgresql'}:
            url = url.set(drivername='postgresql+psycopg')
        if self.app_env in {'demo', 'production'}:
            if url.get_backend_name() != 'postgresql':
                raise RuntimeError('Hosted environments require persistent PostgreSQL')
            if 'sslmode' not in url.query:
                url = url.update_query_dict({'sslmode': 'require'})
        return url


from .storage import Base, User, Challenge, LoginSession, Identity
from .features import register_features, profile_data


def now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def digest(value: str) -> str:
    return sha256(value.encode()).hexdigest()


class EmailInput(BaseModel):
    email: str | None = None
    phone: str | None = None
    identifier: str | None = None
    channel: Literal['email', 'phone'] | None = None

    @model_validator(mode='after')
    def normalize(self):
        import re
        value = (self.identifier or self.phone or self.email or '').strip()
        kind = self.channel or ('phone' if self.phone or value.startswith('+') else 'email')
        if kind == 'phone':
            value = re.sub(r'[\s()\-]', '', value)
            if not re.fullmatch(r'\+[1-9][0-9]{7,14}', value):
                raise ValueError('Номер с кодом страны, например +996700123456')
        else:
            value = str(TypeAdapter(EmailStr).validate_python(value)).lower()
        self.email = value
        self.channel = kind
        return self


class VerifyInput(BaseModel):
    challenge_id: str
    code: str = Field(pattern=r'^\d{5}$')
    nickname: str | None = Field(default=None, min_length=2, max_length=32)

    @field_validator('nickname')
    @classmethod
    def clean_name(cls, value: str | None) -> str | None:
        if value is not None:
            value = value.strip()
            if len(value) < 2:
                raise ValueError('Никнейм: от 2 до 32 символов')
        return value


class RefreshInput(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)


class GoalInput(BaseModel):
    step_goal: int = Field(ge=1000, le=50000)


def create_app(settings: Settings | None = None) -> FastAPI:
    cfg = settings or Settings()
    database_url = cfg.runtime_database_url()
    sqlite = database_url.get_backend_name() == 'sqlite'
    engine = create_engine(
        database_url,
        connect_args={'check_same_thread': False} if sqlite else {'connect_timeout': 15},
        pool_pre_ping=True,
        **({} if sqlite else {'pool_size': 2, 'max_overflow': 3, 'pool_recycle': 300}),
    )
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine, expire_on_commit=False)
    app = FastAPI(title='ADAM RUN', version='0.1.0')
    app.state.sessions = sessions
    app.add_middleware(CORSMiddleware, allow_origins=cfg.cors_origins, allow_methods=['GET', 'POST', 'PATCH'], allow_headers=['Authorization', 'Content-Type'])
    bearer = HTTPBearer(auto_error=False)

    def db():
        with sessions() as session:
            yield session

    def me(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), session: Session = Depends(db)) -> User:
        try:
            if not credentials:
                raise ValueError()
            payload = jwt.decode(credentials.credentials, cfg.jwt_secret, algorithms=['HS256'], audience='adam-run', issuer='adam-run-api', options={'require': ['exp', 'sub', 'sid', 'iss', 'aud']})
            login = session.get(LoginSession, payload['sid'])
            if not login or login.revoked or login.expires_at <= now() or login.user_id != payload['sub']:
                raise ValueError()
            user = session.get(User, payload['sub'])
            if not user:
                raise ValueError()
            return user
        except (jwt.InvalidTokenError, ValueError, KeyError):
            raise HTTPException(401, 'Сессия истекла. Войдите снова.')

    def profile(user: User) -> dict:
        with sessions() as session:
            return profile_data(user, session)

    def tokens(user: User, login: LoginSession, refresh: str) -> dict:
        expires = datetime.now(timezone.utc) + timedelta(minutes=15)
        access = jwt.encode({'sub': user.id, 'sid': login.id, 'exp': expires, 'iss': 'adam-run-api', 'aud': 'adam-run'}, cfg.jwt_secret, algorithm='HS256')
        return {'access_token': access, 'refresh_token': refresh, 'token_type': 'bearer', 'user': profile(user)}

    @app.middleware('http')
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        return response

    @app.get('/health')
    def health():
        with engine.connect() as connection:
            connection.execute(select(1))
        return {'status': 'ok', 'test_auth': cfg.test_auth_enabled, 'environment': cfg.app_env}

    @app.post('/auth/request-code')
    def request_code(body: EmailInput, request: Request, session: Session = Depends(db)):
        if not cfg.test_auth_enabled:
            raise HTTPException(503, 'Email-провайдер пока не настроен')
        stamp = now()
        ip_hash = digest((request.client.host if request.client else 'unknown') + cfg.jwt_secret)
        email_count = session.scalar(select(func.count()).select_from(Challenge).where(Challenge.email == body.email, Challenge.created_at > stamp - timedelta(minutes=10)))
        ip_count = session.scalar(select(func.count()).select_from(Challenge).where(Challenge.ip_hash == ip_hash, Challenge.created_at > stamp - timedelta(minutes=10)))
        if email_count >= 5 or ip_count >= 30:
            raise HTTPException(429, 'Слишком много запросов. Попробуйте через 10 минут.')
        session.execute(update(Challenge).where(Challenge.email == body.email).values(used=True))
        challenge = Challenge(id=str(uuid.uuid4()), email=body.email, ip_hash=ip_hash, created_at=stamp, expires_at=stamp + timedelta(minutes=5), attempts=0, used=False)
        session.add(challenge)
        session.commit()
        return {'challenge_id': challenge.id, 'expires_in': 300, 'test_mode': True}

    @app.post('/auth/verify')
    def verify(body: VerifyInput, session: Session = Depends(db)):
        if not cfg.test_auth_enabled:
            raise HTTPException(503, 'Авторизация недоступна')
        # Conditional update serializes attempts and prevents concurrent OTP replay.
        changed = session.execute(update(Challenge).where(Challenge.id == body.challenge_id, Challenge.used == False, Challenge.attempts < 5, Challenge.expires_at > now()).values(attempts=Challenge.attempts + 1).returning(Challenge.id)).scalar_one_or_none()
        if not changed:
            session.rollback()
            raise HTTPException(400, 'Код истёк или использован. Запросите новый.')
        challenge = session.get(Challenge, body.challenge_id)
        if not hmac.compare_digest(body.code, '00000'):
            session.commit()
            raise HTTPException(400, 'Неверный код')
        challenge.used = True
        identity = session.get(Identity, challenge.email)
        user = session.get(User, identity.user_id) if identity else session.scalar(select(User).where(User.email == challenge.email))
        if not user:
            if not body.nickname:
                session.rollback()
                raise HTTPException(422, 'Для регистрации укажите никнейм')
            uid = str(uuid.uuid4())
            user = User(id=uid, email=challenge.email if '@' in challenge.email else f'phone-{uid}@adam-run.invalid', nickname=body.nickname, step_goal=8000)
            session.add(user)
        session.flush()
        if not identity:
            session.add(Identity(identifier=challenge.email, user_id=user.id, kind='email' if '@' in challenge.email else 'phone'))
        refresh = secrets.token_urlsafe(48)
        login = LoginSession(id=str(uuid.uuid4()), user_id=user.id, refresh_hash=digest(refresh), expires_at=now() + timedelta(days=30), revoked=False)
        session.add(login)
        session.commit()
        return tokens(user, login, refresh)

    @app.post('/auth/refresh')
    def refresh(body: RefreshInput, session: Session = Depends(db)):
        new_token = secrets.token_urlsafe(48)
        sid = session.execute(update(LoginSession).where(LoginSession.refresh_hash == digest(body.refresh_token), LoginSession.revoked == False, LoginSession.expires_at > now()).values(refresh_hash=digest(new_token)).returning(LoginSession.id)).scalar_one_or_none()
        if not sid:
            session.rollback()
            raise HTTPException(401, 'Войдите снова')
        login = session.get(LoginSession, sid)
        user = session.get(User, login.user_id)
        session.commit()
        return tokens(user, login, new_token)

    @app.post('/auth/logout', status_code=204)
    def logout(body: RefreshInput, user: User = Depends(me), credentials: HTTPAuthorizationCredentials = Depends(bearer), session: Session = Depends(db)):
        sid = jwt.decode(credentials.credentials, cfg.jwt_secret, algorithms=['HS256'], audience='adam-run', issuer='adam-run-api')['sid']
        session.execute(update(LoginSession).where(LoginSession.user_id == user.id, LoginSession.id == sid).values(revoked=True))
        session.commit()
        return Response(status_code=204)

    @app.get('/me')
    def get_me(user: User = Depends(me)):
        return profile(user)

    @app.patch('/me/goal')
    def set_goal(body: GoalInput, user: User = Depends(me), session: Session = Depends(db)):
        user.step_goal = body.step_goal
        session.commit()
        return profile(user)

    register_features(app, db, me, now)
    return app


app = create_app()
