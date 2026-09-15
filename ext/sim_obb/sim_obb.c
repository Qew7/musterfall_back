#include "ruby.h"
#include <math.h>
#include <string.h>

#define KERNEL_DOUBLES 8
#define HIT_CLEAR -2
#define HIT_EDGE -1
#define BOARD_EPS 1.0e-6
#define PI 3.14159265358979323846

static const double EPS = 1.0e-12;

static double clampd(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

static double radius(double axis_x, double axis_y, double c, double s, double hw, double hd) {
  return fabs(axis_x * c + axis_y * s) * hd + fabs(-axis_x * s + axis_y * c) * hw;
}

static int separated(
  double dx, double dy, double axis_x, double axis_y,
  double ac, double as, double ahw, double ahd,
  double bc, double bs, double bhw, double bhd
) {
  double dist = fabs(dx * axis_x + dy * axis_y);
  double ra = radius(axis_x, axis_y, ac, as, ahw, ahd);
  double rb = radius(axis_x, axis_y, bc, bs, bhw, bhd);
  return dist > ra + rb + EPS;
}

static int overlap_raw(
  double ax, double ay, double ahw, double ahd, double ac, double as,
  double bx, double by, double bhw, double bhd, double bc, double bs
) {
  double dx = bx - ax;
  double dy = by - ay;
  if (separated(dx, dy, ac, as, ac, as, ahw, ahd, bc, bs, bhw, bhd)) return 0;
  if (separated(dx, dy, -as, ac, ac, as, ahw, ahd, bc, bs, bhw, bhd)) return 0;
  if (separated(dx, dy, bc, bs, ac, as, ahw, ahd, bc, bs, bhw, bhd)) return 0;
  if (separated(dx, dy, -bs, bc, ac, as, ahw, ahd, bc, bs, bhw, bhd)) return 0;
  return 1;
}

static double point_distance(
  double px, double py, double x, double y, double hw, double hd, double c, double s
) {
  double dx = px - x;
  double dy = py - y;
  double lat = -dx * s + dy * c;
  double lng = dx * c + dy * s;
  double dlat = lat - clampd(lat, -hw, hw);
  double dlng = lng - clampd(lng, -hd, hd);
  return hypot(dlat, dlng);
}

static void corner(
  double x, double y, double hw, double hd, double c, double s, int index,
  double *ox, double *oy
) {
  double lng = index < 2 ? hd : -hd;
  double lat = (index == 0 || index == 3) ? -hw : hw;
  *ox = x + (c * lng) - (s * lat);
  *oy = y + (s * lng) + (c * lat);
}

static VALUE rb_overlap(VALUE self,
  VALUE vax, VALUE vay, VALUE vahw, VALUE vahd, VALUE vac, VALUE vas,
  VALUE vbx, VALUE vby, VALUE vbhw, VALUE vbhd, VALUE vbc, VALUE vbs
) {
  int hit = overlap_raw(
    NUM2DBL(vax), NUM2DBL(vay), NUM2DBL(vahw), NUM2DBL(vahd), NUM2DBL(vac), NUM2DBL(vas),
    NUM2DBL(vbx), NUM2DBL(vby), NUM2DBL(vbhw), NUM2DBL(vbhd), NUM2DBL(vbc), NUM2DBL(vbs)
  );
  return hit ? Qtrue : Qfalse;
}

static double distance_raw(
  double ax, double ay, double ahw, double ahd, double ac, double as,
  double bx, double by, double bhw, double bhd, double bc, double bs
) {
  double min = INFINITY;
  int i;
  double px, py, d;

  if (overlap_raw(ax, ay, ahw, ahd, ac, as, bx, by, bhw, bhd, bc, bs)) return 0.0;

  for (i = 0; i < 4; i++) {
    corner(ax, ay, ahw, ahd, ac, as, i, &px, &py);
    d = point_distance(px, py, bx, by, bhw, bhd, bc, bs);
    if (d < min) min = d;
  }
  for (i = 0; i < 4; i++) {
    corner(bx, by, bhw, bhd, bc, bs, i, &px, &py);
    d = point_distance(px, py, ax, ay, ahw, ahd, ac, as);
    if (d < min) min = d;
  }
  return min;
}

static int blocked_by_pad(
  double ax, double ay, double ahw, double ahd, double ac, double as,
  double bx, double by, double bhw, double bhd, double bc, double bs,
  double pad
) {
  return round(distance_raw(ax, ay, ahw, ahd, ac, as, bx, by, bhw, bhd, bc, bs) * 100.0) / 100.0 < pad;
}

static VALUE rb_distance(VALUE self,
  VALUE vax, VALUE vay, VALUE vahw, VALUE vahd, VALUE vac, VALUE vas,
  VALUE vbx, VALUE vby, VALUE vbhw, VALUE vbhd, VALUE vbc, VALUE vbs
) {
  return DBL2NUM(distance_raw(
    NUM2DBL(vax), NUM2DBL(vay), NUM2DBL(vahw), NUM2DBL(vahd), NUM2DBL(vac), NUM2DBL(vas),
    NUM2DBL(vbx), NUM2DBL(vby), NUM2DBL(vbhw), NUM2DBL(vbhd), NUM2DBL(vbc), NUM2DBL(vbs)
  ));
}

static int tray_on_board(
  double x, double y, double hw, double hd, double c, double s, double w, double h
) {
  double rx = fabs(c) * hd + fabs(s) * hw;
  double ry = fabs(s) * hd + fabs(c) * hw;
  return x - rx >= -BOARD_EPS && x + rx <= w + BOARD_EPS &&
    y - ry >= -BOARD_EPS && y + ry <= h + BOARD_EPS;
}

static void heading_trig(double dx, double dy, double *c, double *s) {
  double deg = atan2(dy, dx) * 180.0 / PI;
  deg = fmod(deg, 360.0);
  if (deg < 0.0) deg += 360.0;
  deg *= PI / 180.0;
  *c = cos(deg);
  *s = sin(deg);
}

static double round2(double v) {
  return round(v * 100.0) / 100.0;
}

static const char *kernel_buf(VALUE packed, long *n) {
  long bytes;

  Check_Type(packed, T_STRING);
  bytes = RSTRING_LEN(packed);
  if (bytes % (KERNEL_DOUBLES * (long)sizeof(double)) != 0) {
    rb_raise(rb_eArgError, "packed kernels size");
  }
  *n = bytes / (KERNEL_DOUBLES * (long)sizeof(double));
  return RSTRING_PTR(packed);
}

static long hit_pose(
  double px, double py, double phw, double phd, double pc, double ps,
  const char *raw, long n, long skip, long contact, double reach_pad,
  int check_board, double board_w, double board_h
) {
  long i;
  double pr;

  if (check_board && !tray_on_board(px, py, phw, phd, pc, ps, board_w, board_h)) return HIT_EDGE;
  pr = hypot(phw, phd) + reach_pad;
  for (i = 0; i < n; i++) {
    double k[KERNEL_DOUBLES];
    double dx, dy, reach;

    if (i == skip) continue;
    memcpy(k, raw + (i * KERNEL_DOUBLES * (long)sizeof(double)), sizeof(k));
    dx = px - k[0];
    dy = py - k[1];
    reach = pr + k[6];
    if ((dx * dx) + (dy * dy) > reach * reach) continue;
    if (i == contact) {
      if (overlap_raw(px, py, phw, phd, pc, ps, k[0], k[1], k[2], k[3], k[4], k[5])) return i;
      continue;
    }
    if (blocked_by_pad(px, py, phw, phd, pc, ps, k[0], k[1], k[2], k[3], k[4], k[5], k[7])) return i;
  }
  return HIT_CLEAR;
}

static int segment_open(
  double fx, double fy, double tx, double ty, double phw, double phd,
  const char *raw, long n, long skip, long contact, double reach_pad,
  double board_w, double board_h
) {
  double dx = tx - fx;
  double dy = ty - fy;
  double len = round2(hypot(dx, dy));
  double c, s, mx, my, swept_hd;

  if (len <= 0.05) return 1;
  heading_trig(dx, dy, &c, &s);
  if (hit_pose(tx, ty, phw, phd, c, s, raw, n, skip, contact, reach_pad, 1, board_w, board_h) != HIT_CLEAR) {
    return 0;
  }
  if (!tray_on_board(fx, fy, phw, phd, c, s, board_w, board_h)) return 0;
  mx = (fx + tx) * 0.5;
  my = (fy + ty) * 0.5;
  swept_hd = phd + (len * 0.5);
  return hit_pose(
    mx, my, phw, swept_hd, c, s, raw, n, skip, contact, reach_pad, 0, board_w, board_h
  ) == HIT_CLEAR;
}

static VALUE hit_to_ruby(long hit) {
  if (hit == HIT_CLEAR) return Qnil;
  return LONG2NUM(hit);
}

static VALUE rb_blocker_index(VALUE self,
  VALUE vpx, VALUE vpy, VALUE vphw, VALUE vphd, VALUE vpc, VALUE vps,
  VALUE packed, VALUE vskip, VALUE vcontact, VALUE vreach, VALUE vboard_w, VALUE vboard_h
) {
  double board_w = NUM2DBL(vboard_w);
  long n;
  const char *raw = kernel_buf(packed, &n);

  (void)self;
  return hit_to_ruby(hit_pose(
    NUM2DBL(vpx), NUM2DBL(vpy), NUM2DBL(vphw), NUM2DBL(vphd), NUM2DBL(vpc), NUM2DBL(vps),
    raw, n, NUM2LONG(vskip), NUM2LONG(vcontact), NUM2DBL(vreach),
    board_w > 0.0, board_w, NUM2DBL(vboard_h)
  ));
}

static VALUE rb_segment_clear(VALUE self,
  VALUE vfx, VALUE vfy, VALUE vtx, VALUE vty, VALUE vphw, VALUE vphd,
  VALUE packed, VALUE vskip, VALUE vcontact, VALUE vreach, VALUE vboard_w, VALUE vboard_h
) {
  long n;
  const char *raw = kernel_buf(packed, &n);

  (void)self;
  return segment_open(
    NUM2DBL(vfx), NUM2DBL(vfy), NUM2DBL(vtx), NUM2DBL(vty), NUM2DBL(vphw), NUM2DBL(vphd),
    raw, n, NUM2LONG(vskip), NUM2LONG(vcontact), NUM2DBL(vreach),
    NUM2DBL(vboard_w), NUM2DBL(vboard_h)
  ) ? Qtrue : Qfalse;
}

static VALUE rb_segments_clear(VALUE self,
  VALUE vfx, VALUE vfy, VALUE vphw, VALUE vphd, VALUE packed,
  VALUE vskip, VALUE vcontact, VALUE vreach, VALUE vboard_w, VALUE vboard_h, VALUE dests
) {
  double fx = NUM2DBL(vfx), fy = NUM2DBL(vfy);
  double phw = NUM2DBL(vphw), phd = NUM2DBL(vphd);
  double reach_pad = NUM2DBL(vreach);
  double board_w = NUM2DBL(vboard_w), board_h = NUM2DBL(vboard_h);
  long skip = NUM2LONG(vskip), contact = NUM2LONG(vcontact);
  long kn, bytes, n, i;
  const char *raw;
  const char *dest_raw;
  char *mask;

  (void)self;
  raw = kernel_buf(packed, &kn);
  Check_Type(dests, T_STRING);
  bytes = RSTRING_LEN(dests);
  if (bytes % (2 * (long)sizeof(double)) != 0) rb_raise(rb_eArgError, "packed dests size");
  n = bytes / (2 * (long)sizeof(double));
  dest_raw = RSTRING_PTR(dests);
  mask = ALLOCA_N(char, n);
  for (i = 0; i < n; i++) {
    double dest[2];

    memcpy(dest, dest_raw + (i * 2 * (long)sizeof(double)), sizeof(dest));
    mask[i] = (char)segment_open(
      fx, fy, dest[0], dest[1], phw, phd, raw, kn, skip, contact, reach_pad, board_w, board_h
    );
  }
  return rb_str_new(mask, n);
}

static double normalize_deg(double value) {
  double deg = fmod(value, 360.0);
  if (deg < 0.0) deg += 360.0;
  /* Match Battlefield.normalize_facing, including rounding at half turns. */
  return fmod(deg + 360.0, 360.0);
}

static double shortest_delta(double from, double to) {
  double delta = normalize_deg(to) - normalize_deg(from);
  if (delta > 180.0) return delta - 360.0;
  if (delta < -180.0) return delta + 360.0;
  return delta;
}

static void deg_trig(double facing, double *c, double *s) {
  double rad = normalize_deg(facing) * PI / 180.0;
  *c = cos(rad);
  *s = sin(rad);
}

static int wheel_open(
  double x, double y, double hw, double hd, double c, double s, double facing,
  double heading,
  const char *raw, long n, long skip, long contact, double reach_pad,
  double board_w, double board_h
) {
  double delta = shortest_delta(facing, heading);
  double px, py, vx, vy;
  int steps, index;

  if (fabs(delta) <= 0.05) return 1;
  steps = (int)ceil(fabs(delta) / 10.0);
  if (steps < 8) steps = 8;
  if (steps > 20) steps = 20;

  if (delta < 0.0) corner(x, y, hw, hd, c, s, 0, &px, &py);
  else corner(x, y, hw, hd, c, s, 1, &px, &py);
  vx = x - px;
  vy = y - py;

  for (index = 0; index < steps; index++) {
    double step = delta * ((double)(index + 1) / (double)steps);
    double rad = step * PI / 180.0;
    double ca = cos(rad), sa = sin(rad);
    double nx = px + (vx * ca) - (vy * sa);
    double ny = py + (vx * sa) + (vy * ca);
    double nc, ns;

    nx = clampd(nx, 0.0, board_w - 1.0);
    ny = clampd(ny, 0.0, board_h - 1.0);
    deg_trig(facing + step, &nc, &ns);
    if (hit_pose(
      nx, ny, hw, hd, nc, ns, raw, n, skip, contact, reach_pad, 1, board_w, board_h
    ) != HIT_CLEAR) {
      return 0;
    }
  }
  return 1;
}

static void append_ring(
  double kx, double ky, double khw, double khd, double kc, double ks,
  double clearance, int corners_only, double *xs, double *ys, int *count
) {
  double ihw = khw + clearance;
  double ihd = khd + clearance;
  double cx[4], cy[4];
  int i;

  for (i = 0; i < 4; i++) {
    corner(kx, ky, ihw, ihd, kc, ks, i, &cx[i], &cy[i]);
    xs[*count] = cx[i];
    ys[*count] = cy[i];
    (*count)++;
  }
  if (corners_only) return;
  for (i = 0; i < 4; i++) {
    int j = (i + 1) % 4;
    xs[*count] = (cx[i] + cx[j]) * 0.5;
    ys[*count] = (cy[i] + cy[j]) * 0.5;
    (*count)++;
  }
}

static int fit_tray_on_board(
  double *x, double *y, double hw, double hd, double c, double s,
  double board_w, double board_h
) {
  double rx = fabs(c) * hd + fabs(s) * hw;
  double ry = fabs(s) * hd + fabs(c) * hw;
  double min_x = *x - rx, max_x = *x + rx;
  double min_y = *y - ry, max_y = *y + ry;
  double dx = min_x < 0.0 ? -min_x : 0.0;
  double dy = min_y < 0.0 ? -min_y : 0.0;

  if (max_x + dx > board_w) dx = board_w - max_x;
  if (max_y + dy > board_h) dy = board_h - max_y;
  *x += dx;
  *y += dy;
  return tray_on_board(*x, *y, hw, hd, c, s, board_w, board_h);
}

static VALUE rb_wheel_clear(VALUE self,
  VALUE vx, VALUE vy, VALUE vhw, VALUE vhd, VALUE vc, VALUE vs,
  VALUE vfacing, VALUE vheading, VALUE packed, VALUE vskip, VALUE vcontact,
  VALUE vreach, VALUE vboard_w, VALUE vboard_h
) {
  long n;
  const char *raw = kernel_buf(packed, &n);

  (void)self;
  return wheel_open(
    NUM2DBL(vx), NUM2DBL(vy), NUM2DBL(vhw), NUM2DBL(vhd), NUM2DBL(vc), NUM2DBL(vs),
    NUM2DBL(vfacing), NUM2DBL(vheading),
    raw, n, NUM2LONG(vskip), NUM2LONG(vcontact), NUM2DBL(vreach),
    NUM2DBL(vboard_w), NUM2DBL(vboard_h)
  ) ? Qtrue : Qfalse;
}

static VALUE rb_route_points(VALUE self,
  VALUE vphw, VALUE vphd, VALUE vpc, VALUE vps, VALUE packed,
  VALUE vskip, VALUE vcontact, VALUE vunit_wrap, VALUE vterrain_wrap,
  VALUE vboard_w, VALUE vboard_h, VALUE vreach
) {
  double phw = NUM2DBL(vphw), phd = NUM2DBL(vphd);
  double pc = NUM2DBL(vpc), ps = NUM2DBL(vps);
  double unit_wrap = NUM2DBL(vunit_wrap), terrain_wrap = NUM2DBL(vterrain_wrap);
  double board_w = NUM2DBL(vboard_w), board_h = NUM2DBL(vboard_h);
  double reach_pad = NUM2DBL(vreach);
  double half = phw > phd ? phw : phd;
  double radius = hypot(phw, phd);
  long skip = NUM2LONG(vskip), contact = NUM2LONG(vcontact);
  long kn, i;
  const char *raw;
  double xs[20], ys[20], *out;
  int cap, out_n = 0;
  VALUE result;

  (void)self;
  raw = kernel_buf(packed, &kn);
  if (kn <= 0) return rb_str_new("", 0);

  cap = (int)kn * 20;
  out = ALLOC_N(double, cap * 2);

  for (i = 0; i < kn; i++) {
    double k[KERNEL_DOUBLES];
    double wrap;
    int terrain, extra, count = 0, p;

    if (i == skip || i == contact) continue;
    memcpy(k, raw + (i * KERNEL_DOUBLES * (long)sizeof(double)), sizeof(k));
    terrain = fabs(k[7] - terrain_wrap) <= 1.0e-12;
    wrap = terrain ? terrain_wrap : unit_wrap;
    extra = terrain && radius > half + 0.05;
    append_ring(k[0], k[1], k[2], k[3], k[4], k[5], half + wrap, 0, xs, ys, &count);
    append_ring(k[0], k[1], k[2], k[3], k[4], k[5], (2.0 * half) + wrap, 0, xs, ys, &count);
    if (extra) {
      append_ring(k[0], k[1], k[2], k[3], k[4], k[5], radius + wrap, 1, xs, ys, &count);
    }
    for (p = 0; p < count; p++) {
      double px = xs[p], py = ys[p];
      if (!fit_tray_on_board(&px, &py, phw, phd, pc, ps, board_w, board_h)) continue;
      if (hit_pose(
        px, py, phw, phd, pc, ps, raw, kn, skip, contact, reach_pad, 1, board_w, board_h
      ) != HIT_CLEAR) continue;
      out[out_n++] = px;
      out[out_n++] = py;
    }
  }

  result = rb_str_new((const char *)out, (long)out_n * (long)sizeof(double));
  xfree(out);
  return result;
}

static VALUE rb_closest_point(VALUE self,
  VALUE vpx, VALUE vpy, VALUE vx, VALUE vy, VALUE vhw, VALUE vhd, VALUE vc, VALUE vs
) {
  double px = NUM2DBL(vpx), py = NUM2DBL(vpy);
  double x = NUM2DBL(vx), y = NUM2DBL(vy);
  double hw = NUM2DBL(vhw), hd = NUM2DBL(vhd);
  double c = NUM2DBL(vc), s = NUM2DBL(vs);
  double dx = px - x, dy = py - y;
  double lat = clampd(-dx * s + dy * c, -hw, hw);
  double lng = clampd(dx * c + dy * s, -hd, hd);
  VALUE pair = rb_ary_new_capa(2);
  rb_ary_push(pair, DBL2NUM(x + (-s * lat) + (c * lng)));
  rb_ary_push(pair, DBL2NUM(y + (c * lat) + (s * lng)));
  return pair;
}

void Init_sim_obb(void) {
  VALUE m_sim = rb_define_module("Sim");
  VALUE m_geo = rb_define_module_under(m_sim, "Geometry");
  VALUE m_obb = rb_define_module_under(m_geo, "Obb");
  VALUE m_native = rb_define_module_under(m_obb, "Native");
  rb_define_singleton_method(m_native, "overlap?", rb_overlap, 12);
  rb_define_singleton_method(m_native, "distance", rb_distance, 12);
  rb_define_singleton_method(m_native, "closest_point", rb_closest_point, 8);
  rb_define_singleton_method(m_native, "blocker_index", rb_blocker_index, 12);
  rb_define_singleton_method(m_native, "segment_clear?", rb_segment_clear, 12);
  rb_define_singleton_method(m_native, "segments_clear", rb_segments_clear, 11);
  rb_define_singleton_method(m_native, "wheel_clear?", rb_wheel_clear, 14);
  rb_define_singleton_method(m_native, "route_points", rb_route_points, 12);
}
