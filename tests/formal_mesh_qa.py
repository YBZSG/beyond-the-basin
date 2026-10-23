"""Dependency-free UV triangle validation shared by authored GLB tests."""
import collections

def cross(a, b, p):
    return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])


def area(points):
    return abs(sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(points, points[1:]+points[:1])))*.5


def intersection_area(subject, clip):
    """Convex triangle clipping; edge-only adjacency has zero positive area."""
    winding = 1 if cross(*clip) >= 0 else -1
    output = list(subject)
    for a, b in zip(clip, clip[1:]+clip[:1]):
        old, output = output, []
        if not old:
            break
        start = old[-1]
        d_start = cross(a, b, start)*winding
        for end in old:
            d_end = cross(a, b, end)*winding
            if (d_start >= 0) != (d_end >= 0):
                fraction = d_start/(d_start-d_end)
                output.append(tuple(start[i]+fraction*(end[i]-start[i]) for i in (0, 1)))
            if d_end >= 0:
                output.append(end)
            start, d_start = end, d_end
    return area(output) if len(output) > 2 else 0.0


def uv_overlap_check(triangles):
    buckets = collections.defaultdict(list)
    candidates = set()
    bounds = []
    for index, triangle in enumerate(triangles):
        low = tuple(min(v[d] for v in triangle) for d in (0, 1))
        high = tuple(max(v[d] for v in triangle) for d in (0, 1))
        bounds.append((low, high))
        for y in range(int(low[1]*32), int(high[1]*32)+1):
            for x in range(int(low[0]*32), int(high[0]*32)+1):
                key = (x, y)
                for other in buckets[key]:
                    candidates.add((other, index))
                buckets[key].append(index)
    checked = 0
    for a, b in candidates:
        al, ah = bounds[a]
        bl, bh = bounds[b]
        if any(min(ah[d], bh[d])-max(al[d], bl[d]) <= 1e-10 for d in (0, 1)):
            continue
        checked += 1
        overlap = intersection_area(triangles[a], triangles[b])
        if overlap > max(1e-10, min(area(triangles[a]), area(triangles[b]))*.001):
            raise AssertionError(f'UV2 positive-area overlap between triangles {a}, {b}: {overlap}')
    return checked

