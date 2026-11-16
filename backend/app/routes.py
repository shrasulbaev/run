"""Server-owned routes and sequential GPS validation. Client totals are untrusted."""
import json
import math
from pathlib import Path

CATALOG = {r['id']: r for r in json.loads((Path(__file__).resolve().parents[1] / 'data/routes.json').read_text())}


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    x = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371008.8 * 2 * math.atan2(math.sqrt(x), math.sqrt(max(0, 1-x)))


def samples(route):
    points = [(lat, lon) for lon, lat in route['geometry']['coordinates']]
    result = [points[0]]
    for a, b in zip(points, points[1:]):
        count = max(1, math.ceil(distance(a, b)/15))
        result.extend((a[0]+(b[0]-a[0])*i/count, a[1]+(b[1]-a[1])*i/count) for i in range(1, count+1))
    return result


SAMPLES = {key: samples(route) for key, route in CATALOG.items()}


def validate_trace(route_id, trace, elapsed_ms):
    route = CATALOG[route_id]
    path = SAMPLES[route_id]
    maximum_speed = 3.5 if route['mode'] == 'walk' else 10.0
    if elapsed_ms < route['distance_m'] / maximum_speed * 1000:
        raise ValueError('Слишком короткое время прохождения.')
    if len(trace) < 10:
        raise ValueError('Недостаточно точек GPS для проверки маршрута.')
    index, last = 0, None
    for fix in trace:
        if fix.mocked:
            raise ValueError('Результаты с тестовой геолокацией не засчитываются.')
        point = (fix.lat, fix.lon)
        if last is not None:
            dt = (fix.time_ms - last.time_ms) / 1000
            if dt <= 0:
                raise ValueError('Нарушена последовательность GPS.')
            movement = distance(point, (last.lat, last.lon))
            if movement > 20 and movement/dt > maximum_speed:
                raise ValueError('Обнаружен скачок GPS или слишком высокая скорость.')
        if distance(point, path[index]) > 45:
            raise ValueError('Маршрут пройден не полностью или нарушен порядок точек.')
        for candidate in range(index + 1, min(index + 5, len(path))):
            if distance(point, path[candidate]) <= 18:
                index = candidate
            else:
                break
        last = fix
    if index < len(path) - 1:
        raise ValueError('Не пройдены все участки маршрута.')
    trace_ms = trace[-1].time_ms - trace[0].time_ms
    if trace_ms < route['distance_m'] / maximum_speed * 1000:
        raise ValueError('Временные метки GPS не соответствуют дистанции.')
    return trace_ms
