class_name EventData
extends RefCounted

## Things that happen to you between the Edicts.
##
## One arrives every dozen turns or so. Each is a small, legible choice with
## no obviously correct answer — usually gold against growth, or an advantage
## now against how the neighbours feel about you.
##
## An option may carry any of:
##   gold, progress          immediate
##   m                       permanent modifiers, merged like an Edict
##   pop_capital, pop_all    population, added or (negative) taken
##   unit                    a free unit of that line, at the capital
##   xp_all                  experience for every unit you own
##   heal_all                every unit restored
##   diplo_all               every rival's opinion of you
##   gold_per_city           one-off gold, multiplied by your cities

const LIST := [
{"id": "caravan", "title": "A Caravan Asks to Winter",
 "text": "Two hundred people and four hundred animals want to sit out the cold inside your borders. They have money, and they have somewhere else to be in spring.",
 "options": [
   {"label": "Charge them for it", "desc": "+150 gold", "gold": 150},
   {"label": "Let them stay for nothing", "desc": "Every rival thinks better of you", "diplo_all": 14.0},
   {"label": "Learn their roads", "desc": "+1 movement inside your borders, for good", "m": {"mv_border": 1}},
 ]},

{"id": "refugees", "title": "Refugees at the Border",
 "text": "A war you are not in has emptied a valley two weeks' walk away. The people from it are at your gate, and they are not armed.",
 "options": [
   {"label": "Settle them", "desc": "+1 population in every city", "pop_all": 1},
   {"label": "Take the fighting men", "desc": "A free soldier of your age", "unit": "melee"},
   {"label": "Send them on", "desc": "+120 gold saved, and the neighbours notice", "gold": 120, "diplo_all": -8.0},
 ]},

{"id": "seam", "title": "A Rich Seam",
 "text": "A collapsed hillside has opened something worth digging. Your engineers disagree, at length, about what to do with it.",
 "options": [
   {"label": "Mine it hard", "desc": "+2 production in every city", "m": {"p_prod": 2}},
   {"label": "Sell the rights", "desc": "+90 gold for every city you hold", "gold_per_city": 90},
   {"label": "Study it", "desc": "+3 progress in every city", "m": {"p_sci": 3}},
 ]},

{"id": "plague", "title": "Fever in the Low Streets",
 "text": "It started by the water and it is moving uphill. The physicians want money; the priests want a procession; the magistrates want the gates shut.",
 "options": [
   {"label": "Pay the physicians", "desc": "180 gold, and it passes", "gold": -180},
   {"label": "Shut the gates", "desc": "Lose 1 population in every city", "pop_all": -1},
   {"label": "Let it burn out", "desc": "Lose 2 population in your capital, but learn from it",
    "pop_capital": -2, "m": {"p_sci": 2}},
 ]},

{"id": "triumph", "title": "Your General Wants a Triumph",
 "text": "He has won something, or says he has. He would like a parade, and he would like you to pay for it.",
 "options": [
   {"label": "Give him his day", "desc": "120 gold; every unit you own gains experience",
    "gold": -120, "xp_all": 25},
   {"label": "Give him a title instead", "desc": "Free; +1 free unit of upkeep per city", "m": {"upkeep_free": 1}},
   {"label": "Refuse him", "desc": "+80 gold, and the army remembers", "gold": 80, "m": {"s_all": -2}},
 ]},

{"id": "scholar", "title": "A Scholar at the Gate",
 "text": "She has walked a long way with a box of instruments and an unreasonable confidence about the shape of the world.",
 "options": [
   {"label": "Fund her", "desc": "100 gold, then +20% progress for good", "gold": -100, "m": {"pct_sci": 0.20}},
   {"label": "Buy her instruments", "desc": "A Breakthrough's worth of progress now", "progress": 1},
   {"label": "Send her to a rival", "desc": "+60 gold and their goodwill", "gold": 60, "diplo_all": 10.0},
 ]},

{"id": "road", "title": "An Older Road",
 "text": "Under the mud there is paving, and it goes somewhere your maps do not.",
 "options": [
   {"label": "Follow it", "desc": "The land around it is revealed", "reveal": 4},
   {"label": "Repave it", "desc": "+3 gold in every city", "m": {"p_gold": 3}},
   {"label": "Break it for stone", "desc": "+1 production in every city and +100 gold",
    "m": {"p_prod": 1}, "gold": 100},
 ]},

{"id": "deserters", "title": "Deserters in the Hills",
 "text": "Somebody else's soldiers, unpaid for a season, camped inside your border and openly for hire.",
 "options": [
   {"label": "Hire them", "desc": "120 gold for two seasoned soldiers",
    "gold": -120, "unit": "melee", "unit2": "ranged", "unit_xp": 40},
   {"label": "Drive them out", "desc": "Your units are restored", "heal_all": true},
   {"label": "Send them home", "desc": "Their nation is grateful", "diplo_all": 16.0},
 ]},

{"id": "harvest", "title": "A Year Without Winter",
 "text": "The barley came twice. Nobody can explain it and nobody is complaining.",
 "options": [
   {"label": "Store it", "desc": "+2 food in every city, for good", "m": {"p_food": 2}},
   {"label": "Sell the surplus", "desc": "+110 gold for every city you hold", "gold_per_city": 110},
   {"label": "Feast on it", "desc": "+1 population everywhere, and every rival is invited",
    "pop_all": 1, "diplo_all": 8.0},
 ]},

{"id": "envoy", "title": "An Envoy With an Offer",
 "text": "He represents somebody who would rather you were friendly, and has been given a budget to make that happen.",
 "options": [
   {"label": "Take the money", "desc": "+240 gold; the others hear of it", "gold": 240, "diplo_all": -10.0},
   {"label": "Take the treaty", "desc": "Every rival warms considerably", "diplo_all": 22.0},
   {"label": "Take the maps", "desc": "The land around you is revealed", "reveal": 6},
 ]},

{"id": "forge", "title": "A New Way of Working Iron",
 "text": "A smith in a back street has been doing something to the quenching that nobody taught her.",
 "options": [
   {"label": "Put her in the armoury", "desc": "Melee units +6 strength", "m": {"s_melee": 6}},
   {"label": "Put her in the yard", "desc": "Units cost 15% less", "m": {"unit_pct": -0.15}},
   {"label": "Sell the method", "desc": "+200 gold", "gold": 200},
 ]},

{"id": "omen", "title": "An Omen Over the Capital",
 "text": "Something crossed the sky at dusk and the whole city saw it. Everyone agrees it means something; nobody agrees what.",
 "options": [
   {"label": "Declare it a blessing", "desc": "Every unit you own gains a rank's worth of experience", "xp_all": 35},
   {"label": "Declare it a warning", "desc": "Cities +50 defence", "m": {"city_hp": 50}},
   {"label": "Say nothing", "desc": "+4 progress in every city", "m": {"p_sci": 4}},
 ]},

{"id": "flotilla", "title": "Boats on the Water",
 "text": "Fishermen from somewhere further along the coast, blown off course, and impressed by your harbour.",
 "options": [
   {"label": "Keep them", "desc": "+1 food and +1 gold on every water tile you work",
    "m": {"t_gold_water": 1}, "pop_capital": 1},
   {"label": "Buy their charts", "desc": "80 gold, and your units may cross water", "gold": -80, "m": {"embark": 1}},
   {"label": "Escort them home", "desc": "+130 gold in thanks and their goodwill", "gold": 130, "diplo_all": 8.0},
 ]},

{"id": "heir", "title": "A Question of Succession",
 "text": "It is not urgent. It is, however, being discussed loudly in three separate rooms.",
 "options": [
   {"label": "Name a soldier", "desc": "+10% strength when attacking", "m": {"pct_atk": 0.10}},
   {"label": "Name a builder", "desc": "Structures cost 20% less", "m": {"struct_pct": -0.20}},
   {"label": "Name a merchant", "desc": "+25% gold", "m": {"pct_gold": 0.25}},
 ]},

{"id": "monument", "title": "The Stone Is Already Quarried",
 "text": "Someone, at some expense, has cut a great deal of stone and then died without saying what it was for.",
 "options": [
   {"label": "Raise a wall with it", "desc": "Cities +60 defence and +6 strength",
    "m": {"city_hp": 60, "city_str": 6}},
   {"label": "Raise a hall with it", "desc": "+2 gold and +2 progress in every city",
    "m": {"p_gold": 2, "p_sci": 2}},
   {"label": "Sell it to a rival", "desc": "+220 gold, and they are delighted",
    "gold": 220, "diplo_all": 6.0},
 ]},
]
