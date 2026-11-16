"""Profiles, sanitized photos, verified route results and public rankings."""
import base64
import binascii
import io
import json
import uuid
from datetime import timedelta
from hashlib import sha256

from fastapi import Depends, HTTPException, Response
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select, update, func
from sqlalchemy.orm import Session

from .storage import User, Identity, UserDetails, Attempt, Activity
from .routes import CATALOG, validate_trace


def profile_data(user, session):
    details = session.get(UserDetails, user.id)
    identities = session.scalars(select(Identity).where(Identity.user_id == user.id)).all()
    contacts = {i.kind: i.identifier for i in identities}
    return {'id': user.id, 'email': contacts.get('email', user.email if not user.email.endswith('@adam-run.invalid') else None),
            'phone': contacts.get('phone'), 'nickname': user.nickname, 'step_goal': user.step_goal,
            'city': details.city if details else 'Бишкек', 'bio': details.bio if details else '',
            'avatar_version': details.avatar_version if details else None}


def public_data(user, session):
    d = session.get(UserDetails, user.id)
    return {'id': user.id, 'nickname': user.nickname, 'avatar_version': d.avatar_version if d else None}


def activity_data(a):
    route = CATALOG[a.route_id]
    return {'id': a.id, 'route_id': a.route_id, 'route_name': route['name'], 'mode': route['mode'],
            'completed_at': a.completed_at.isoformat()+'Z', 'elapsed_ms': a.elapsed_ms,
            'moving_ms': a.moving_ms, 'distance_m': a.distance_m, 'ranked': a.ranked}


def achievements(activities):
    ids = {a.route_id for a in activities}
    result = []
    if activities: result.append({'id': 'first', 'name': 'Первый финиш', 'description': 'Завершён первый маршрут'})
    if 'city-bird' in ids: result.append({'id': 'artist', 'name': 'Городской художник', 'description': 'Нарисована Городская птица'})
    if 'park-sprint' in ids: result.append({'id': 'runner', 'name': 'На скорости', 'description': 'Завершён Парковый Sprint'})
    if len({(a.completed_at+timedelta(hours=6)).date() for a in activities}) >= 3:
        result.append({'id': 'regular', 'name': 'В своём ритме', 'description': 'Активность в 3 разных дня'})
    return result


class EditProfile(BaseModel):
    nickname: str = Field(min_length=2, max_length=32)
    city: str = Field(default='Бишкек', max_length=60)
    bio: str = Field(default='', max_length=250)
    @field_validator('nickname', 'city', 'bio')
    @classmethod
    def clean(cls, v):
        return v.strip()


class PhotoInput(BaseModel):
    image_base64: str | None = Field(default=None, max_length=4_000_000)


class AttemptInput(BaseModel):
    route_id: str


class Fix(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lon: float = Field(ge=-180, le=180, allow_inf_nan=False)
    accuracy: float = Field(ge=0, le=25, allow_inf_nan=False)
    time_ms: int = Field(ge=0)
    mocked: bool = False


class FinishInput(BaseModel):
    id: uuid.UUID
    route_id: str
    attempt_id: uuid.UUID | None = None
    elapsed_ms: int = Field(gt=0, le=86_400_000)
    moving_ms: int = Field(gt=0, le=86_400_000)
    trace: list[Fix] = Field(min_length=10, max_length=5000)


def register_features(app, db, me, now):
    def details(user, session):
        d = session.get(UserDetails, user.id)
        if not d:
            d = UserDetails(user_id=user.id, city='Бишкек', bio='')
            session.add(d)
        return d

    @app.patch('/me/profile')
    def edit(body: EditProfile, user: User = Depends(me), session: Session = Depends(db)):
        if len(body.nickname) < 2: raise HTTPException(422, 'Никнейм: от 2 символов')
        d = details(user, session)
        user.nickname, d.city, d.bio = body.nickname, body.city, body.bio
        session.commit()
        return profile_data(user, session)

    @app.post('/me/photo')
    def upload(body: PhotoInput, user: User = Depends(me), session: Session = Depends(db)):
        d = details(user, session)
        if body.image_base64 is None:
            d.avatar = d.avatar_version = None
        else:
            try:
                raw = base64.b64decode(body.image_base64, validate=True)
                with Image.open(io.BytesIO(raw)) as im:
                    if im.width * im.height > 20_000_000: raise ValueError()
                    im = ImageOps.exif_transpose(im).convert('RGB')
                    im = ImageOps.fit(im, (512, 512))
                    out = io.BytesIO()
                    im.save(out, format='JPEG', quality=82, optimize=True)
                    d.avatar = out.getvalue()
                    d.avatar_version = sha256(d.avatar).hexdigest()[:16]
            except (ValueError, binascii.Error, UnidentifiedImageError, OSError, Image.DecompressionBombError):
                raise HTTPException(422, 'Выберите фото JPG, PNG или WebP до 3 МБ и 20 Мп.')
        session.commit()
        return profile_data(user, session)

    @app.get('/users/{user_id}/photo')
    def photo(user_id: str, user: User = Depends(me), session: Session = Depends(db)):
        d = session.get(UserDetails, user_id)
        if not d or not d.avatar: raise HTTPException(404, 'Фото не добавлено')
        return Response(d.avatar, media_type='image/jpeg')

    @app.get('/users/{user_id}')
    def public_profile(user_id: str, user: User = Depends(me), session: Session = Depends(db)):
        other = session.get(User, user_id)
        if not other: raise HTTPException(404, 'Участник не найден')
        activities = session.scalars(select(Activity).where(Activity.user_id == user_id)).all()
        ids = {a.route_id for a in activities}
        return {**public_data(other, session), 'achievements': achievements(activities),
                'completed_routes': [r for r in CATALOG.values() if r['id'] in ids]}

    @app.get('/me/activity')
    def history(user: User = Depends(me), session: Session = Depends(db)):
        rows = session.scalars(select(Activity).where(Activity.user_id == user.id).order_by(Activity.completed_at.desc())).all()
        return {'activities': [activity_data(a) for a in rows[:100]], 'achievements': achievements(rows),
                'total': len(rows), 'distance_m': sum(a.distance_m for a in rows),
                'time_ms': sum(a.moving_ms for a in rows), 'drawings': len({a.route_id for a in rows if CATALOG[a.route_id]['mode']=='walk'})}

    @app.post('/attempts')
    def begin(body: AttemptInput, user: User = Depends(me), session: Session = Depends(db)):
        if body.route_id not in CATALOG: raise HTTPException(404, 'Маршрут не найден')
        recent = session.scalar(select(func.count()).select_from(Attempt).where(Attempt.user_id==user.id, Attempt.started_at>now()-timedelta(hours=1)))
        if recent >= 30: raise HTTPException(429, 'Слишком много стартов. Попробуйте позже.')
        a = Attempt(id=str(uuid.uuid4()), user_id=user.id, route_id=body.route_id, started_at=now(), completed=False)
        session.add(a); session.commit()
        return {'id': a.id, 'started_at': a.started_at.isoformat()+'Z'}

    @app.post('/activities')
    def finish(body: FinishInput, user: User = Depends(me), session: Session = Depends(db)):
        old = session.get(Activity, str(body.id))
        if old:
            if old.user_id != user.id: raise HTTPException(409, 'Идентификатор уже занят')
            return activity_data(old)
        if body.route_id not in CATALOG: raise HTTPException(404, 'Маршрут не найден')
        if body.moving_ms > body.elapsed_ms: raise HTTPException(422, 'Некорректное время')
        try: trace_ms = validate_trace(body.route_id, body.trace, body.elapsed_ms)
        except ValueError as e: raise HTTPException(422, str(e))
        if trace_ms > body.elapsed_ms + 5000: raise HTTPException(422, 'Время GPS превышает время прохождения')
        stamp, elapsed, ranked = now(), body.elapsed_ms, False
        started = stamp-timedelta(milliseconds=elapsed)
        if body.attempt_id:
            a = session.get(Attempt, str(body.attempt_id))
            if not a or a.user_id != user.id or a.route_id != body.route_id:
                raise HTTPException(422, 'Старт маршрута не подтверждён')
            server_ms = int((stamp-a.started_at).total_seconds()*1000)
            if server_ms < trace_ms - 5000: raise HTTPException(422, 'Время не подтверждено сервером')
            if server_ms <= 86_400_000:
                changed = session.execute(update(Attempt).where(Attempt.id==a.id, Attempt.completed==False).values(completed=True)).rowcount
                if not changed: raise HTTPException(409, 'Этот старт уже завершён')
                elapsed, started, ranked = max(server_ms, body.elapsed_ms), a.started_at, True
        a = Activity(id=str(body.id), user_id=user.id, route_id=body.route_id, completed_at=stamp,
                     started_at=started, elapsed_ms=elapsed, moving_ms=body.moving_ms,
                     distance_m=CATALOG[body.route_id]['distance_m'], ranked=ranked,
                     evidence_hash=sha256(json.dumps([p.model_dump() for p in body.trace], sort_keys=True).encode()).hexdigest(), sample_count=len(body.trace))
        session.add(a); session.commit()
        return activity_data(a)

    @app.get('/rankings/{route_id}')
    def rankings(route_id: str, period: str = 'month', user: User = Depends(me), session: Session = Depends(db)):
        if route_id not in CATALOG: raise HTTPException(404, 'Маршрут не найден')
        if period not in ('month','all'): raise HTTPException(422, 'Неизвестный период')
        q = select(Activity).where(Activity.route_id==route_id, Activity.ranked==True)
        if period=='month':
            local = now()+timedelta(hours=6)
            start = local.replace(day=1,hour=0,minute=0,second=0,microsecond=0)-timedelta(hours=6)
            q=q.where(Activity.completed_at>=start)
        rows = session.scalars(q).all()
        grouped = {}
        walk = CATALOG[route_id]['mode']=='walk'
        for a in rows: grouped.setdefault(a.user_id, []).append(a)
        scores = {uid: len({(a.completed_at+timedelta(hours=6)).date() for a in aa}) if walk else min(a.elapsed_ms for a in aa) for uid,aa in grouped.items()}
        ordered = sorted(scores, key=lambda uid: ((-scores[uid] if walk else scores[uid]), uid))
        entries, rank, previous = [], 0, None
        for index, uid in enumerate(ordered):
            if scores[uid] != previous: rank=index+1
            previous=scores[uid]
            entries.append({**public_data(session.get(User,uid),session), 'rank':rank, 'score':scores[uid], 'is_me':uid==user.id})
        return {'entries':entries[:50], 'me':next((e for e in entries if e['is_me']),None), 'participants':len(entries),
                'period':period, 'route_id':route_id, 'metric':'days' if walk else 'time',
                'rule':'Один балл за день с завершённым рисунком. Скорость не важна.' if walk else 'Лучшее время полного маршрута. Паузы входят в результат.',
                'rewards':'Места и достижения. Партнёрских призов пока нет.'}
