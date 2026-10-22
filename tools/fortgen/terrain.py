"""Geometrie-Hilfen fuer das Gelaende (Polygone aus der .fwe-Datei)."""
import math


def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xi > x:
                inside = not inside
    return inside


def _closest_on_segment(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2))
    return (ax + t * dx, ay + t * dy)


class Terrain:
    def __init__(self, polygons):
        self.polys = polygons

    def inside(self, p):
        return any(point_in_poly(p, poly) for poly in self.polys)

    def nearest_surface(self, p):
        best, bestd = None, 1e18
        for poly in self.polys:
            for i in range(len(poly)):
                q = _closest_on_segment(p, poly[i], poly[(i + 1) % len(poly)])
                d = math.dist(p, q)
                if d < bestd:
                    best, bestd = q, d
        return best, bestd

    def segment_clear(self, a, b, step=8.0, end_margin=12.0):
        """True, wenn die Strebe a-b nicht durch Fels geht (Enden duerfen auf dem Boden liegen)."""
        L = math.dist(a, b)
        n = max(2, int(L / step))
        for i in range(1, n):
            t = i / n
            if t * L < end_margin or (1 - t) * L < end_margin:
                continue
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if self.inside(q) and self.nearest_surface(q)[1] > 4:
                return False
        return True
