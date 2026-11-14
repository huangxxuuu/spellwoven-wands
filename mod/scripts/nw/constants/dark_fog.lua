return {
    sources={radius=2,min_duration=3,max_duration=5,interval=.1,overlap=.3,per_owner=128,world_limit=384,
        fade_duration=.4,cell=4,merge_max_width=1,merge_radius_divisor=2,remove_tail=.2,
        merge_min_remaining=.5,world_spawns_per_window=32,owner_spawns_per_window=16,
        min_trail_length=.00001,teleport_distance=16,distance_epsilon=.000001},
    control={radius=3,fear_time=1,blind_time=.8,shadow_speed=1.25,fear_cooldown=2,walk_speed=4,
        min_walk_distance=.5,walk_padding=.25,path_attempts=1,wander_min_duration=.25,
        wander_duration_range=.25,search_interval=.25,chase_duration=.1},
    boss={moose_radius=5.5,moose_cooldown=8,eye_cooldown=8,sector_arc=180,
        signature={max_upvalues=100,ice_radius=1,ice_spawn_time=.25,sector_timeline_count=2,area_radius=3}},
}
