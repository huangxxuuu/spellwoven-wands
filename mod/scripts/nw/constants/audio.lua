return {
    cards={
        chord_d={radius=3,mana=10,delay=0.03},
    },
    timing={half_beat=.5,double_beat=2,normal_beat=1,mark_duration=2,mark_height=.8,mark_parent_height=1},
    instruments={
        ocarina={notes={{"A",21},{"B",23},{"C",12},{"D",14},{"E",16},{"F",17},{"G#",20},{"A2",21}},tier=1,mana=6,speed=14,lifetime=.45,halfangle=1},
        kantele={notes={{"A",21},{"D",14},{"D#",12},{"E",16},{"G",19}},tier=2,mana=10,radius=3},
        extra_notes={{"kantele_f","F",17},{"kantele_b","B",23}},ocarina_g_pitch=19,delay=.03,base_octave=3,semitones_per_octave=12,
    },
    pitch_cards={
        {"pitch_octave_up","升八度",12},{"pitch_octave_down","降八度",-12},
        {"pitch_semitone_up","升半音",1},{"pitch_semitone_down","降半音",-1},
    },
    pitch_cost={mana=1,delay=0,tier=1},
}
