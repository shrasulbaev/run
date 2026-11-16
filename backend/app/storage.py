from datetime import datetime
from sqlalchemy import Boolean, DateTime, Integer, String, LargeBinary, ForeignKey, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


# Keep the original tables compatible with installed v1 clients. All new schema
# is additive; no user rows or sessions are rewritten by the deployment.
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


class Identity(Base):
    __tablename__ = 'user_identities'
    identifier: Mapped[str] = mapped_column(String(254), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    kind: Mapped[str] = mapped_column(String(10))
    __table_args__ = (Index('identity_user_kind', 'user_id', 'kind', unique=True),)


class ContactLink(Base):
    __tablename__ = 'contact_links'
    challenge_id: Mapped[str] = mapped_column(ForeignKey('auth_challenges.id'), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'))


class UserDetails(Base):
    __tablename__ = 'user_details'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    city: Mapped[str] = mapped_column(String(60), default='Бишкек')
    bio: Mapped[str] = mapped_column(String(250), default='')
    avatar: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    avatar_version: Mapped[str | None] = mapped_column(String(64), nullable=True)


class Attempt(Base):
    __tablename__ = 'route_attempts'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    route_id: Mapped[str] = mapped_column(String(60))
    started_at: Mapped[datetime] = mapped_column(DateTime)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)


class Activity(Base):
    __tablename__ = 'activities'
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    route_id: Mapped[str] = mapped_column(String(60), index=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    started_at: Mapped[datetime] = mapped_column(DateTime)
    elapsed_ms: Mapped[int] = mapped_column(Integer)
    moving_ms: Mapped[int] = mapped_column(Integer)
    distance_m: Mapped[int] = mapped_column(Integer)
    ranked: Mapped[bool] = mapped_column(Boolean)
    evidence_hash: Mapped[str] = mapped_column(String(64))
    sample_count: Mapped[int] = mapped_column(Integer)
