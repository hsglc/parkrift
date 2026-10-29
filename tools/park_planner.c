// Hybrid A* parking planner for the level designer (tools/design_levels.py).
//
// Finds a drivable way for the game's car (44 x 22 units, bicycle model with a minimum turning
// radius, forward and reverse) from a start pose into a bay, so every level is proven solvable
// with the real car, and reports how hard the way is: its length, the number of gear changes
// (back-and-forth manoeuvres) and the smallest gap between the car and anything along it.
//
// Build: cc -O2 -shared -fPIC -o park_planner.so park_planner.c -lm
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define CAR_L 44.0
#define CAR_W 22.0
#define XY_CELL 4.0
#define TH_BINS 72
#define STEP 6.0

typedef struct {
    float x, y, th, g, f;
    int parent;
    signed char dir;
    signed char steer;
    int switches;
    float clear;
    float length;
} Node;

static const unsigned char *occ;   // 1 = blocked, 1 unit cells
static const float *dist;          // distance to the nearest blocked cell
static int W, H;

static int blocked(double x, double y) {
    int ix = (int)x, iy = (int)y;
    if (ix < 0 || iy < 0 || ix >= W || iy >= H) return 1;
    return occ[iy * W + ix];
}

static double gap(double x, double y) {
    int ix = (int)x, iy = (int)y;
    if (ix < 0 || iy < 0 || ix >= W || iy >= H) return 0;
    return dist[iy * W + ix];
}

// The car's outline and inside, sampled every 2-3 units: blocked if any sample is
static int collides(double x, double y, double th, double *clearance) {
    // Far from everything: the car's circumscribed circle is clear
    double free_r = gap(x, y);
    if (free_r > 26) {
        if (clearance) *clearance = free_r - 24.6;
        return 0;
    }
    double c = cos(th), s = sin(th);
    double best = 1e9;
    for (double a = -CAR_L / 2; a <= CAR_L / 2 + 1e-6; a += 2.75) {
        for (double b = -CAR_W / 2; b <= CAR_W / 2 + 1e-6; b += 2.75) {
            double px = x + a * c - b * s, py = y + a * s + b * c;
            if (blocked(px, py)) return 1;
            int edge = fabs(a) > CAR_L / 2 - 1.5 || fabs(b) > CAR_W / 2 - 1.5;
            if (edge && clearance) {
                double d = gap(px, py);
                if (d < best) best = d;
            }
        }
    }
    if (clearance) *clearance = best;
    return 0;
}

typedef struct { int *items; float *keys; int n, cap; } Heap;

static void push(Heap *h, int item, float key) {
    if (h->n == h->cap) {
        h->cap = h->cap ? h->cap * 2 : 1024;
        h->items = realloc(h->items, sizeof(int) * h->cap);
        h->keys = realloc(h->keys, sizeof(float) * h->cap);
    }
    int i = h->n++;
    while (i > 0) {
        int p = (i - 1) / 2;
        if (h->keys[p] <= key) break;
        h->items[i] = h->items[p];
        h->keys[i] = h->keys[p];
        i = p;
    }
    h->items[i] = item;
    h->keys[i] = key;
}

static int pop(Heap *h) {
    int top = h->items[0];
    int item = h->items[--h->n];
    float key = h->keys[h->n];
    int i = 0;
    for (;;) {
        int l = 2 * i + 1, r = l + 1, m = i;
        float mk = key;
        if (l < h->n && h->keys[l] < mk) { m = l; mk = h->keys[l]; }
        if (r < h->n && h->keys[r] < mk) { m = r; mk = h->keys[r]; }
        if (m == i) break;
        h->items[i] = h->items[m];
        h->keys[i] = h->keys[m];
        i = m;
    }
    h->items[i] = item;
    h->keys[i] = key;
    return top;
}

// Cost-to-go over the lot for a point that keeps `r` from everything (8-way Dijkstra on cells of
// XY_CELL units from the bay): a far better guide than the straight line in mazes
static float *togo;
static int tw, th_;

static void build_togo(double gx, double gy, double r) {
    tw = (int)(W / XY_CELL) + 1; th_ = (int)(H / XY_CELL) + 1;
    int cells = tw * th_;
    togo = realloc(togo, sizeof(float) * cells);
    for (int i = 0; i < cells; i++) togo[i] = 1e9f;
    Heap q = {0};
    int g = (int)(gy / XY_CELL) * tw + (int)(gx / XY_CELL);
    togo[g] = 0;
    push(&q, g, 0);
    static const int dx[8] = {1, -1, 0, 0, 1, 1, -1, -1}, dy[8] = {0, 0, 1, -1, 1, -1, 1, -1};
    while (q.n) {
        float key = q.keys[0];
        int c = pop(&q);
        if (key > togo[c]) continue;
        int cx = c % tw, cy = c / tw;
        for (int k = 0; k < 8; k++) {
            int nx = cx + dx[k], ny = cy + dy[k];
            if (nx < 0 || ny < 0 || nx >= tw || ny >= th_) continue;
            double px = (nx + 0.5) * XY_CELL, py = (ny + 0.5) * XY_CELL;
            if (gap(px, py) < r) continue;
            float nd = togo[c] + (float)(XY_CELL * (k < 4 ? 1 : 1.4142));
            if (nd < togo[ny * tw + nx]) { togo[ny * tw + nx] = nd; push(&q, ny * tw + nx, nd); }
        }
    }
    free(q.items); free(q.keys);
}

static double heuristic(double x, double y, double bx, double by) {
    int cx = (int)(x / XY_CELL), cy = (int)(y / XY_CELL);
    double straight = hypot(bx - x, by - y);
    if (cx < 0 || cy < 0 || cx >= tw || cy >= th_) return straight;
    float v = togo[cy * tw + cx];
    return v > 1e8f ? straight : (v > straight ? v : straight);
}

static double wrap(double a) {
    while (a > M_PI) a -= 2 * M_PI;
    while (a < -M_PI) a += 2 * M_PI;
    return a;
}

// Goal: the whole car inside the bay, straight enough, and (reverse) nose toward `out`
static int in_bay(double x, double y, double th, const double *bay, double tol, int reverse, double ox, double oy) {
    double bc = cos(bay[4]), bs = sin(bay[4]);
    double c = cos(th), s = sin(th);
    for (int i = 0; i < 4; i++) {
        double a = (i & 1 ? 1 : -1) * CAR_L / 2, b = (i & 2 ? 1 : -1) * CAR_W / 2;
        double px = x + a * c - b * s - bay[0], py = y + a * s + b * c - bay[1];
        double lx = px * bc + py * bs, ly = -px * bs + py * bc;
        if (fabs(lx) > bay[2] / 2 || fabs(ly) > bay[3] / 2) return 0;
    }
    double mis = fabs(remainder(th - bay[4], M_PI));
    if (mis > tol) return 0;
    if (reverse && c * ox + s * oy <= 0) return 0;
    return 1;
}

/*
 * occupancy, distance: w*h grids. start: x, y, heading. bay: cx, cy, length, width, angle.
 * radius: minimum turning radius. tol: alignment tolerance (rad). reverse: must end nose toward
 * (ox, oy). out: [found, length, switches, min clearance, expansions, reverse length].
 */
int plan(const unsigned char *occupancy, const float *distance, int w, int h,
         const double *start, const double *bay, double radius, double tol, int reverse,
         double ox, double oy, int max_expansions, double *out) {
    occ = occupancy; dist = distance; W = w; H = h;
    memset(out, 0, sizeof(double) * 6);
    build_togo(bay[0], bay[1], 8);
    int gw = (int)(w / XY_CELL) + 1, gh = (int)(h / XY_CELL) + 1;
    size_t cells = (size_t)gw * gh * TH_BINS * 2;
    int *closed = malloc(sizeof(int) * cells);
    for (size_t i = 0; i < cells; i++) closed[i] = -1;
    int cap = 1 << 20, n = 0;
    Node *nodes = malloc(sizeof(Node) * cap);
    Heap heap = {0};
    double c0;
    if (collides(start[0], start[1], start[2], &c0)) { free(closed); free(nodes); out[0] = -1; return 0; }
    nodes[n] = (Node){(float)start[0], (float)start[1], (float)start[2], 0, 0, -1, 1, 0, 0, (float)c0, 0};
    push(&heap, n++, 0);
    double k[5] = {-1 / radius, -0.5 / radius, 0, 0.5 / radius, 1 / radius};
    int expansions = 0, found = -1;
    while (heap.n && expansions < max_expansions) {
        int id = pop(&heap);
        Node cur = nodes[id];
        int gx = (int)(cur.x / XY_CELL), gy = (int)(cur.y / XY_CELL);
        int gt = ((int)floor((wrap(cur.th) + M_PI) / (2 * M_PI) * TH_BINS)) % TH_BINS;
        size_t key = (((size_t)gy * gw + gx) * TH_BINS + gt) * 2 + (cur.dir > 0);
        if (closed[key] >= 0) continue;
        closed[key] = id;
        expansions++;
        if (in_bay(cur.x, cur.y, cur.th, bay, tol, reverse, ox, oy)) { found = id; break; }
        for (int dir = -1; dir <= 1; dir += 2) {
            for (int si = 0; si < 5; si++) {
                double x = cur.x, y = cur.y, th = cur.th, clear = cur.clear, cl;
                int ok = 1;
                for (int sub = 0; sub < 3; sub++) {
                    double ds = dir * STEP / 3;
                    th += ds * k[si];
                    x += ds * cos(th);
                    y += ds * sin(th);
                    if (collides(x, y, th, &cl)) { ok = 0; break; }
                    if (cl < clear) clear = cl;
                }
                if (!ok) continue;
                int sw = cur.parent >= 0 && dir != cur.dir;
                double cost = STEP * (dir < 0 ? 1.4 : 1.0) + (sw ? 45 : 0) + (si != 2 ? 0.6 : 0);
                double g = cur.g + cost;
                double hcost = heuristic(x, y, bay[0], bay[1]);
                if (n == cap) { cap *= 2; nodes = realloc(nodes, sizeof(Node) * cap); }
                nodes[n] = (Node){(float)x, (float)y, (float)th, (float)g, (float)(g + hcost), id, (signed char)dir,
                                  (signed char)si, cur.switches + sw, (float)clear, cur.length + (float)STEP};
                push(&heap, n++, (float)(g + hcost));
            }
        }
    }
    out[4] = expansions;
    if (found >= 0) {
        Node f = nodes[found];
        out[0] = 1;
        out[1] = f.length;
        out[2] = f.switches;
        out[3] = f.clear;
        double back = 0;
        for (int i = found; i >= 0 && nodes[i].parent >= 0; i = nodes[i].parent)
            if (nodes[i].dir < 0) back += STEP;
        out[5] = back;
    }
    free(closed); free(nodes); free(heap.items); free(heap.keys);
    return found >= 0;
}
