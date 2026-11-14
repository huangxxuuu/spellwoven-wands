return {
    feedback={interval=30},
    permanent_motion={timeout_minutes=16,max_elapsed_minutes=20,seconds_per_minute=60,threshold=20,interval=1},
    live_options={0,25,50,100,200,300,400,500,600,700,800},legacy_live_limit=200,
    range_options={0,60,120,240,480,960},legacy_range=30,migrated_range=60,max_depth=30,
    request={max_integer=2147483647,max_snapshot_length=128,max_key_length=40,interval=.1,timeout=5},
    trail={options={0,100,500,900,1300,1700,2100,2500,2900,3300},other_fraction=.75,
        legacy={[200]=500,[400]=500,[600]=900,[700]=900,[800]=900,
            [1000]=1300,[1600]=1700,[1900]=2100,[2000]=2100}},
}
