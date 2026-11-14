return {
    ground_height_epsilon=.0001,velocity_epsilon_squared=.000001,distance_epsilon=.001,
    orbit={min_radius=2.5,radius_scale=3.2,reference_speed=25,max_radius=8,stiffness=100,damping=20,
        max_acceleration=180,owner_jump_squared=16,return_margin=1.5,return_radius_fraction=.5,
        heading_radius=.05,max_turn_rate=210,max_radial_speed=8,radial_speed_fraction=.5,radius_response=.25},
    spiral_speed_mult=.6,
    acceleration={initial_factor=.55,gain=.9,duration=.7},
    homing={behind_penalty=100,score_turn_rate=240,min_score_speed=.1,search_interval=.1,
        turn_rate=360,near_force=72,force=36,near_damping=1.44,damping=.72},
    returning={reverse_delay=.45,delay=.4,turn_rate=180},
    field={drag_half_life=4,stop_speed=.1},
}
