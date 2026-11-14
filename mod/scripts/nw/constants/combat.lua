return {
    query_cell_size=4,
    collision_radius=.5,
    direction_epsilon=.001,
    geometry_length_squared_epsilon=1e-12,
    clear_step=.4,
    safe_move={query_padding=2,steps_per_unit=4,step=.25},
    electric={source_height=.65,range_padding=1},
    knockback={query_padding=3,min_distance=.05,step=.15,anchor_offset=.25,radius=1,strength=.40,anchor_lifetime=.5},
}
