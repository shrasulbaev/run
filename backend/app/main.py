"""ADAM RUN development API. The fixed OTP can never run in production."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256
import hmac
import secrets
import uuid

import jwt
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import Boolean, DateTime, Integer, String, create_engine, func, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    app_env: str = 'development'
    test_auth_enabled: bool = True
    database_url: str = 'sqlite:///./adam_run.db'
    jwt_secret: str = 'local-development-only-change-before-sharing'
    cors_origins: list[str] = ['http://localhost:7357', 'http://127.0.0.1:7357']


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    nickname: Mapped[str] = mapped_column(String(32))
    step_goal: Mapped[int] = mapped_column(Integer, default=8000)


class Challenge(Base):
    __tablename__ = 'auth_challenges'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), index=True)
    ip_hash: Mapped[str] = mapped_column(String(64), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    used: Mapped[bool] = mapped_column(Boolean, default=False)


class LoginSession(Base):
    __tablename__ = 'login_sessions'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    refresh_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)


def now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def digest(value: str) -> str:
    return sha256(value.encode()).hexdigest()


class EmailInput(BaseModel):
    email: EmailStr

    @field_validator('email')
    @classmethod
    def normalize(cls, value: str) -> str:
        return value.strip().lower()


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
    if cfg.app_env not in {'development', 'test'} and cfg.test_auth_enabled:
        raise RuntimeError('Fixed test OTP is forbidden outside development/test')
    if cfg.app_env not in {'development', 'test'} and cfg.jwt_secret.startswith('local-'):
        raise RuntimeError('Configure a strong JWT_SECRET')
    engine = create_engine(cfg.database_url, connect_args={'check_same_thread': False} if cfg.database_url.startswith('sqlite') else {})
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
        return {'id': user.id, 'email': user.email, 'nickname': user.nickname, 'step_goal': user.step_goal, 'city': 'Бишкек'}

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
        return {'status': 'ok', 'test_auth': cfg.test_auth_enabled}

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
        user = session.scalar(select(User).where(User.email == challenge.email))
        if not user:
            if not body.nickname:
                session.rollback()
                raise HTTPException(422, 'Для регистрации укажите никнейм')
            user = User(id=str(uuid.uuid4()), email=challenge.email, nickname=body.nickname, step_goal=8000)
            session.add(user)
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

    return app


app = create_app()
