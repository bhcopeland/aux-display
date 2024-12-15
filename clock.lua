require 'cairo'

function clock_draw()
    local cs = cairo_create(cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, conky_window.width, conky_window.height))

    -- Clock center and radius
    local center_x, center_y, radius = 231, 240, 100

    -- Get current time
    local hours = tonumber(os.date("%I"))
    local minutes = tonumber(os.date("%M"))
    local seconds = tonumber(os.date("%S"))

    -- Draw clock face
    cairo_set_source_rgba(cs, 0.8, 0.8, 0.8, 0.8) -- Clock face color
    cairo_arc(cs, center_x, center_y, radius, 0, 2 * math.pi)
    cairo_fill(cs)

    -- Draw clock hands
    draw_hand(cs, center_x, center_y, radius * 0.6, hours / 12 * 2 * math.pi - math.pi / 2, 4, 0, 0, 0) -- Hour hand
    draw_hand(cs, center_x, center_y, radius * 0.8, minutes / 60 * 2 * math.pi - math.pi / 2, 2, 0, 0, 0) -- Minute hand
    draw_hand(cs, center_x, center_y, radius * 0.9, seconds / 60 * 2 * math.pi - math.pi / 2, 1, 1, 0, 0) -- Second hand

    cairo_destroy(cs)
end

function draw_hand(cr, x, y, length, angle, width, r, g, b)
    cairo_set_line_width(cr, width)
    cairo_set_source_rgba(cr, r, g, b, 1)
    cairo_move_to(cr, x, y)
    cairo_line_to(cr, x + length * math.cos(angle), y + length * math.sin(angle))
    cairo_stroke(cr)
end

