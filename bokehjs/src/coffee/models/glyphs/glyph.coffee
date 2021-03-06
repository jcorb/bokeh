_ = require "underscore"
rbush = require "rbush"

CategoricalMapper = require "../mappers/categorical_mapper"
Renderer = require "../renderers/renderer"
p = require "../../core/properties"
bbox = require "../../core/util/bbox"
Model = require "../../model"

class GlyphView extends Renderer.View

  initialize: (options) ->
    super(options)

    @renderer = options.renderer

    # Init gl (this should really be done anytime renderer is set,
    # and not done if it isn't ever set, but for now it only
    # matters in the unit tests because we build a view without a
    # renderer there)
    if @renderer?.plot_view?
      ctx = @renderer.plot_view.canvas_view.ctx
      if ctx.glcanvas?
        @_init_gl(ctx.glcanvas.gl)

  render: (ctx, indices, data) ->

    if @mget("visible")
      ctx.beginPath();

      if @glglyph?
        if @_render_gl(ctx, indices, data)
          return

      @_render(ctx, indices, data)

    return

  _render_gl: (ctx, indices, mainglyph) ->
    # Get transform
    wx = wy = 1  # Weights to scale our vectors
    [dx, dy] = @renderer.map_to_screen([0*wx, 1*wx, 2*wx], [0*wy, 1*wy, 2*wy])
    # Try again, but with weighs so we're looking at ~100 in screen coordinates
    wx = 100 / Math.min(Math.max(Math.abs(dx[1] - dx[0]), 1e-12), 1e12)
    wy = 100 / Math.min(Math.max(Math.abs(dy[1] - dy[0]), 1e-12), 1e12)
    [dx, dy] = @renderer.map_to_screen([0*wx, 1*wx, 2*wx], [0*wy, 1*wy, 2*wy])
    # Test how linear it is
    if (Math.abs((dx[1] - dx[0]) - (dx[2] - dx[1])) > 1e-6 ||
        Math.abs((dy[1] - dy[0]) - (dy[2] - dy[1])) > 1e-6)
      return false

    trans =
        width: ctx.glcanvas.width, height: ctx.glcanvas.height,
        dx: dx, dy: dy, sx: (dx[1]-dx[0])/wx, sy: (dy[1]-dy[0])/wy
    @glglyph.draw(indices, mainglyph, trans)
    return true  # success

  bounds: () ->
    if not @index?
      return bbox.empty()
    bb = @index.data.bbox
    return @_bounds([
      [bb[0], bb[2]],
      [bb[1], bb[3]]
    ])

  # glyphs that need more sophisticated "snap to data" behaviour (like
  # snapping to a patch centroid, e.g, should override these
  scx: (i) -> return @sx[i]
  scy: (i) -> return @sy[i]

  # any additional customization can happen here
  _init_gl: () -> false


  _xy_index: () ->
    index = rbush()
    pts = []

    # if the range is categorical, map to synthetic coordinates first
    if @renderer.xmapper instanceof CategoricalMapper.Model
      xx = @renderer.xmapper.v_map_to_target(@x, true)
    else
      xx = @x
    if @renderer.ymapper instanceof CategoricalMapper.Model
      yy = @renderer.ymapper.v_map_to_target(@y, true)
    else
      yy = @y

    for i in [0...xx.length]
      x = xx[i]
      if isNaN(x) or not isFinite(x)
        continue
      y = yy[i]
      if isNaN(y) or not isFinite(y)
        continue
      pts.push([x, y, x, y, {'i': i}])

    index.load(pts)
    return index

  sdist: (mapper, pts, spans, pts_location="edge", dilate=false) ->
    if _.isString(pts[0])
      pts = mapper.v_map_to_target(pts)

    if pts_location == 'center'
      halfspan = (d / 2 for d in spans)
      pt0 = (pts[i] - halfspan[i] for i in [0...pts.length])
      pt1 = (pts[i] + halfspan[i] for i in [0...pts.length])
    else
      pt0 = pts
      pt1 = (pt0[i] + spans[i] for i in [0...pt0.length])

    spt0 = mapper.v_map_to_target(pt0)
    spt1 = mapper.v_map_to_target(pt1)

    if dilate
      return (Math.ceil(Math.abs(spt1[i] - spt0[i])) for i in [0...spt0.length])
    else
      return (Math.abs(spt1[i] - spt0[i]) for i in [0...spt0.length])

  get_reference_point: () ->
    reference_point = @mget('reference_point')
    if _.isNumber(reference_point)
      return @data[reference_point]
    else
      return reference_point

  draw_legend: (ctx, x0, x1, y0, y1) -> null

  _generic_line_legend: (ctx, x0, x1, y0, y1) ->
    reference_point = @get_reference_point() ? 0
    ctx.save()
    ctx.beginPath()
    ctx.moveTo(x0, (y0 + y1) /2)
    ctx.lineTo(x1, (y0 + y1) /2)
    if @visuals.line.doit
      @visuals.line.set_vectorize(ctx, reference_point)
      ctx.stroke()
    ctx.restore()

  _generic_area_legend: (ctx, x0, x1, y0, y1) ->
    reference_point = @get_reference_point() ? 0
    indices = [reference_point]

    w = Math.abs(x1-x0)
    dw = w*0.1
    h = Math.abs(y1-y0)
    dh = h*0.1

    sx0 = x0 + dw
    sx1 = x1 - dw

    sy0 = y0 + dh
    sy1 = y1 - dh

    if @visuals.fill.doit
      @visuals.fill.set_vectorize(ctx, reference_point)
      ctx.fillRect(sx0, sy0, sx1-sx0, sy1-sy0)

    if @visuals.line.doit
      ctx.beginPath()
      ctx.rect(sx0, sy0, sx1-sx0, sy1-sy0)
      @visuals.line.set_vectorize(ctx, reference_point)
      ctx.stroke()

class Glyph extends Renderer.Model

  # Many glyphs have simple x and y coordinates. Override this in
  # subclasses that use other coordinates
  coords: [ ['x', 'y'] ]

  mixins: ['line', 'fill']

  props: ->
    return _.extend {}, super(), {
      visible: [ p.Bool, true ]
    }

module.exports =
  Model: Glyph
  View: GlyphView
