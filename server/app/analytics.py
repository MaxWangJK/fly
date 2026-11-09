"""Only installation (1) and daily open (2). Never read business repositories.

The random code identifies an installation, not a person or hardware. No account,
address, IP, platform, app version, headers or request contents are persisted.
"""
from datetime import datetime, time, timedelta, timezone
import logging
from pathlib import Path
import re
import secrets
from zoneinfo import ZoneInfo
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from sqlalchemy import Date, cast, case, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .models import AnalyticsDevice, AnalyticsDailyActive, now

STATS_ZONE = ZoneInfo('Asia/Shanghai')
CODE = re.compile(r'[A-Za-z0-9]{8,32}\Z', re.ASCII)
_dashboard = Path(__file__).with_name('analytics_dashboard.html').read_text(encoding='utf-8')


class AnalyticsAccessLogFilter(logging.Filter):
    def filter(self, record):
        # Uvicorn's request arguments contain both client IP and the URL code.
        # Suppress the whole record instead of redacting only one component.
        return '/api/stats/' not in unquote(record.getMessage()).lower()


def install_analytics_log_filter():
    logger = logging.getLogger('uvicorn.access')
    if not any(isinstance(item, AnalyticsAccessLogFilter) for item in logger.filters):
        logger.addFilter(AnalyticsAccessLogFilter())


def _insert_once(db, model, values, keys):
    dialect = db.bind.dialect.name
    insert = pg_insert if dialect == 'postgresql' else sqlite_insert if dialect == 'sqlite' else None
    if insert is None:
        raise RuntimeError('Unsupported analytics database')
    db.execute(insert(model).values(**values).on_conflict_do_nothing(index_elements=keys))


def record_action(sessions, code, action):
    stamp = now()
    with sessions.begin() as db:
        _insert_once(db, AnalyticsDevice, {
            'device_code': code, 'first_seen_at': stamp,
            'last_seen_at': stamp, 'created_at': stamp,
        }, ['device_code'])
        if action == 2:
            _insert_once(db, AnalyticsDailyActive, {
                'device_code': code, 'active_date': stamp.astimezone(STATS_ZONE).date(),
                'created_at': stamp,
            }, ['device_code', 'active_date'])
            db.execute(update(AnalyticsDevice).where(AnalyticsDevice.device_code == code).values(
                last_seen_at=case((AnalyticsDevice.last_seen_at < stamp, stamp),
                                  else_=AnalyticsDevice.last_seen_at)))


def _start(day):
    return datetime.combine(day, time.min, STATS_ZONE).astimezone(timezone.utc)


def _cohort_date(db, days=0):
    column = AnalyticsDevice.first_seen_at
    if db.bind.dialect.name == 'postgresql':
        return cast(func.timezone('Asia/Shanghai', column), Date) + days
    return func.date(column, '+8 hours', f'+{days} days')


def overview(db):
    stamp = now()
    today = stamp.astimezone(STATS_ZONE).date()
    tomorrow = today + timedelta(days=1)
    total = db.scalar(select(func.count()).select_from(AnalyticsDevice))
    new_today = db.scalar(select(func.count()).select_from(AnalyticsDevice).where(
        AnalyticsDevice.first_seen_at >= _start(today), AnalyticsDevice.first_seen_at < _start(tomorrow)))

    def active(start, end):
        return db.scalar(select(func.count(func.distinct(AnalyticsDailyActive.device_code))).where(
            AnalyticsDailyActive.active_date >= start, AnalyticsDailyActive.active_date <= end))

    retention = {}
    for days in (1, 7, 30):
        mature = AnalyticsDevice.first_seen_at < _start(today - timedelta(days=days) + timedelta(days=1))
        eligible = db.scalar(select(func.count()).select_from(AnalyticsDevice).where(mature))
        retained = db.scalar(select(func.count()).select_from(AnalyticsDevice).join(
            AnalyticsDailyActive,
            (AnalyticsDailyActive.device_code == AnalyticsDevice.device_code) &
            (AnalyticsDailyActive.active_date == _cohort_date(db, days)),
        ).where(mature))
        retention[f'd{days}'] = {'eligible_installs': eligible, 'retained': retained,
            'rate_percent': round(retained * 100 / eligible, 2) if eligible else None}

    first = today - timedelta(days=29)
    cohort_day = _cohort_date(db)
    installs = dict(db.execute(select(cohort_day, func.count()).where(
        AnalyticsDevice.first_seen_at >= _start(first),
        AnalyticsDevice.first_seen_at < _start(tomorrow),
    ).group_by(cohort_day)).all())
    daily = dict(db.execute(select(AnalyticsDailyActive.active_date, func.count()).where(
        AnalyticsDailyActive.active_date >= first, AnalyticsDailyActive.active_date <= today,
    ).group_by(AnalyticsDailyActive.active_date)).all())
    installs = {str(day): count for day, count in installs.items()}
    daily = {str(day): count for day, count in daily.items()}
    trends = [{'date': str(first + timedelta(days=i)),
               'installs': installs.get(str(first + timedelta(days=i)), 0),
               'active': daily.get(str(first + timedelta(days=i)), 0)} for i in range(30)]
    return {'timezone': 'Asia/Shanghai', 'server_date': str(today),
        'total_installs': total, 'today_installs': new_today,
        'today_active': active(today, today),
        'yesterday_active': active(today - timedelta(days=1), today - timedelta(days=1)),
        'last_7_days_active_unique': active(today - timedelta(days=6), today),
        'last_30_days_active_unique': active(first, today),
        'retention': retention, 'trends': trends}


def create_analytics_router(settings, sessions):
    install_analytics_log_filter()
    router = APIRouter()
    basic = HTTPBasic(auto_error=False)

    def admin(credentials: HTTPBasicCredentials | None = Depends(basic)):
        password = settings.analytics_admin_password
        if not password or not password.get_secret_value():
            raise HTTPException(404, 'Not found')
        user_ok = secrets.compare_digest(
            (credentials.username if credentials else '').encode(), settings.analytics_admin_username.encode())
        password_ok = secrets.compare_digest(
            (credentials.password if credentials else '').encode(), password.get_secret_value().encode())
        if not (user_ok and password_ok):
            raise HTTPException(401, 'Admin authentication required', headers={'WWW-Authenticate': 'Basic realm="Fly Analytics"'})

    @router.post('/api/stats/{device_code}/{action}', include_in_schema=False)
    async def statistics(device_code: str, action: str, request: Request):
        if not CODE.fullmatch(device_code) or action not in ('1', '2'):
            return Response(status_code=400)
        if request.query_params or await request.body():
            return Response(status_code=400)
        try:
            await run_in_threadpool(record_action, sessions, device_code, int(action))
        except SQLAlchemyError:
            # Never emit a traceback containing bound codes alongside request IPs.
            return Response(status_code=503, headers={'Cache-Control': 'no-store'})
        return Response(status_code=200, headers={'Cache-Control': 'no-store'})

    @router.get('/api/admin/stats/overview', dependencies=[Depends(admin)])
    def statistics_overview(response: Response):
        response.headers['Cache-Control'] = 'no-store'
        with sessions() as db:
            return overview(db)

    @router.get('/api/admin/stats', dependencies=[Depends(admin)], include_in_schema=False)
    def statistics_dashboard():
        nonce = secrets.token_urlsafe(24)
        return HTMLResponse(_dashboard.replace('__NONCE__', nonce), headers={
            'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff',
            'Content-Security-Policy': f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'",
        })

    return router
