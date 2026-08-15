#include "ruby.h"
#include <math.h>

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

static VALUE rb_distance(VALUE self,
  VALUE vax, VALUE vay, VALUE vahw, VALUE vahd, VALUE vac, VALUE vas,
  VALUE vbx, VALUE vby, VALUE vbhw, VALUE vbhd, VALUE vbc, VALUE vbs
) {
  double ax = NUM2DBL(vax), ay = NUM2DBL(vay), ahw = NUM2DBL(vahw), ahd = NUM2DBL(vahd);
  double ac = NUM2DBL(vac), as = NUM2DBL(vas);
  double bx = NUM2DBL(vbx), by = NUM2DBL(vby), bhw = NUM2DBL(vbhw), bhd = NUM2DBL(vbhd);
  double bc = NUM2DBL(vbc), bs = NUM2DBL(vbs);
  double min = INFINITY;
  int i;
  double px, py, d;

  if (overlap_raw(ax, ay, ahw, ahd, ac, as, bx, by, bhw, bhd, bc, bs)) {
    return DBL2NUM(0.0);
  }

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
  return DBL2NUM(min);
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
}
