-- Baseline natural death materials, audited against DST 761239 (design workbook,
-- sheet 生物索引). Only direct recipe ingredients are listed. Conditional forms
-- are selected at settlement; inventory contents and recipe loot are excluded.
local catalog = {}
local function family(materials, names)
    local set = {}
    for material in materials:gmatch("%S+") do set[material] = true end
    for name in names:gmatch("%S+") do catalog[name] = set end
end
family("", [[abigail archive_centipede bat_boss bearger bernie_active bernie_big
bird_mutant bird_mutant_spitter bunnyman carrat catcoon chester cookiecutter crabking crabking_claw
deer deerclops dustmoth eyeofterror eyeofterror_mini eyeplant friendlyfruitfly frog fruitdragon
fruitfly fused_shadeling gestalt_guard gestalt_guard_evolved ghost gingerbreadpig glommer gnarwail
grassgekko graveguard_ghost hedgehound hutch koalefant_summer koalefant_winter lavae
lavae_pet little_walrus lordfruitfly lunar_grazer lunarfrog lunarthrall_plant lureplant
mandrake_active merm mermguard mermking minotaur mole molebat monkey moonbutterfly
mutatedbearger mutatedbird mutatedbuzzard_gestalt mutatedwarg otter perd pigelite1 pigelite2
pigelite3 pigelite4 pigguard pigman polly_rogers powder_monkey prime_mate rabbit
rabbitking_aggressive rabbitking_lucky rabbitking_passive rabbitkingminion_bunnyman salty_dog
sharkboi smallbird spat stalker_minion tallbird teenbird tentacle_pillar_arm toadstool
toadstool_dark vault_crawler waterplant wobster_moonglass_land wobster_sheller_land worm worm_boss]])
family("stinger", [[bee killerbee beeguard beequeen]])
family("goose_feather", [[moose mossling]])
family("batwing", [[bat]])
family("batwing nitre", [[bat_acid]])
family("beefalowool", [[babybeefalo beefalo]])
family("bluegem", [[deer_blue]])
family("bluegem goldnugget greengem orangegem purplegem redgem yellowgem", [[dragonfly]])
family("bluegem houndstooth", [[icehound]])
family("bluegem yellowgem malbatross_beak", [[malbatross]])
family("butterflywings", [[butterfly]])
family("charcoal", [[klaus krampus]])
family("feather_canary", [[canary]])
family("feather_crow", [[buzzard crow penguin puffin]])
family("feather_robin", [[robin]])
family("feather_robin_winter", [[robin_winter]])
family("flint nitre rocks", [[rocky_acid rocky_boss_acid]])
family("flint rocks", [[crabking_mob crabking_mob_knight rocky rocky_boss shark]])
family("gears", [[alterguardian_phase4_lunarrift daywalker2 knight knight_yoth rook wagdrone_flying wagdrone_rolling]])
family("gears greengem nightmarefuel yellowgem shieldofterror", [[twins]])
family("gears nightmarefuel", [[knight_nightmare rook_nightmare]])
family("gears purplegem", [[bishop]])
family("houndstooth", [[chest_mimic_revealed clayhound claywarg gingerbreadwarg hound mutatedhound warg warglet]])
family("houndstooth redgem", [[firehound]])
family("ice", [[mutated_penguin mutateddeerclops]])
family("lightbulb", [[lightflier slurper squid yots_worm]])
family("lightbulb slurtle_shellpieces", [[lightcrab]])
family("lightninggoathorn", [[lightninggoat]])
family("livinglog", [[leif leif_sparse mushgnome]])
family("moonrocknugget", [[alterguardian_phase3]])
family("moonrocknugget rocks", [[vault_pillar_guard]])
family("mosquitosack", [[mosquito]])
family("nightmarefuel", [[bat_boss_shadow bunnyman_shadowloot charlie_boss_runner crawlinghorror crawlingnightmare daywalker
gelblob itemmimic_revealed merm_shadow mermguard_shadow monkey_shadowloot nightmarebeak oceanhorror
rabbit_shadowloot rocky_boss_shadow ruins_shadeling ruinsnightmare shadow_bishop shadow_knight
shadow_leech shadow_rook shadowthrall_centipede_controller shadowthrall_hands shadowthrall_horns
shadowthrall_mouth shadowthrall_parasite shadowthrall_wings shrouden stalker stalker_atrium
stalker_forest terrorbeak worm_boss_shadow]])
family("nightmarefuel purplegem", [[bishop_nightmare]])
family("redgem", [[deer_red]])
family("rocks", [[antlion cave_vent_mite]])
family("rocks tentaclespike tentaclespots", [[tentacle_pillar]])
family("silk", [[spider spider_dropper spider_healer spider_hider spider_moon spider_spitter spider_warrior
spider_water spiderqueen]])
family("slurtle_shellpieces slurtleslime", [[slurtle snurtle]])
family("tentaclespike tentaclespots", [[tentacle]])
family("tentaclespots", [[merm_lunar mermguard_lunar]])
family("twigs", [[birchnutdrake grassgator]])
family("walrus_tusk", [[walrus]])
return catalog
