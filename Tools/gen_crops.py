# Generates every crop in the Sorry pack: produce item, crop data, seed packet,
# and the two market goods that price them.
#
# Prices are not hand-picked. Each crop earns roughly the same gold per day it
# occupies a plot, scaled by a rarity tier, and the seed costs a third of what
# the planting is expected to return. That way a slow crop is worth waiting for,
# a cheap one is worth planting twice, and no crop is accidentally the only
# correct answer.
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent.parent
CROPS = HERE / 'Assets' / 'Crops'
MARKET = HERE / 'Assets' / 'Market'

GOLD_PER_DAY = 7.0
SEED_SHARE = 0.34
REGROW_LIFE = 1.8     # a regrowing plant holds its plot longer, so earns longer
REGROW_PICKS = 3      # and is picked about three times

# rarity -> (multiplier, how many the town absorbs before the price sags, drift)
TIER = {
    'common':   (1.00, 36.0, 0.18),
    'uncommon': (1.30, 24.0, 0.22),
    'rare':     (1.70, 16.0, 0.27),
    'exotic':   (2.20, 10.0, 0.32),
}

SPR, SUM, AUT, WIN = 1, 2, 4, 8

# group, index, name, rarity, days per stage, produce per pick, regrows, seasons, blurb
TABLE = [
 ('A', 0,'Corn','common',2,2,False,SUM|AUT,"Two ears a stalk and a long summer to fill them."),
 ('A', 1,'Carrot','common',1,1,False,SPR|SUM,"Quick and cheap. The crop to fall back on when a spike is too far off to wait for."),
 ('A', 2,'Cauliflower','rare',2,1,False,SPR,"Slow and dear, and worth a great deal when the town wants one. A missed spring is a missed year."),
 ('A', 3,'Beetroot','common',2,1,False,SPR|AUT,"Keeps in a cellar, which is why the town will take it in any week."),
 ('A', 4,'Eggplant','uncommon',2,2,False,SUM|AUT,"Two to a plant, which makes it the steady earner \u2014 and the one most likely to glut its own price."),
 ('A', 5,'Cabbage','uncommon',2,1,False,AUT|WIN,"Hardy enough for the cold months, when almost nothing else is."),
 ('A', 6,'Broccoli','uncommon',2,1,False,AUT|WIN,"Stands through frost. Half the winter catalogue is this and its cousins."),
 ('A', 7,'Parsnip','common',2,1,False,WIN,"Sweetens in the frost. The one root that would rather be planted in winter."),
 ('A', 8,'Pumpkin','uncommon',3,1,False,AUT,"Fifteen days, so it must go in the ground by the middle of autumn or not at all."),
 ('A', 9,'Turnip','common',1,1,False,SPR|WIN,"Five days in the cold. What a winter farm lives on."),
 ('A',10,'Radicchio','uncommon',2,1,False,AUT|WIN,"Bitter, red, and in demand exactly when the fields are otherwise bare."),
 ('A',11,'Plum','rare',3,2,True,SUM,"Takes a fortnight to come in and then keeps giving. Plant it early or not at all."),
 ('A',12,'Starfruit','exotic',3,1,False,SUM,"The most the town will pay for one thing. Also the longest wait, and the smallest appetite for a second."),
 ('A',13,'Cucumber','common',2,2,True,SUM,"Picked again and again off the same vine. Cheap each, plentiful together."),
 ('B', 0,'Sunflower','uncommon',2,1,False,SUM|AUT,"Grown for the seed, sold by the head."),
 ('B', 1,'Ginger','uncommon',2,1,False,SUM,"A root the kitchens want and the fields rarely give."),
 ('B', 2,'Potato','common',2,2,False,SPR|AUT,"Two to a plant and the town never tires of them. The safest money on the shelf."),
 ('B', 3,'Green Pepper','uncommon',2,2,True,SUM,"Keeps fruiting all summer once it starts."),
 ('B', 4,'Aubergine','uncommon',2,2,False,SUM|AUT,"The long purple sort. Grows where the eggplant does and sells beside it."),
 ('B', 5,'Blue Melon','rare',3,1,False,SUM,"A fortnight of summer for one melon, and the town pays accordingly."),
 ('B', 6,'Peas','common',1,3,True,SPR,"Three a pod, picked over and over. The crop that fills a satchel fastest."),
 ('B', 7,'Pineapple','exotic',3,1,False,SUM,"Fifteen days of summer sun for a single fruit. A gamble, and priced like one."),
 ('B', 8,'Honeydew','rare',3,1,False,SUM,"Slow, sweet, and ruined by a frost. Summer only, and not the end of it."),
 ('B', 9,'Yam','uncommon',2,2,False,AUT|WIN,"Lifts late and stores through the cold."),
 ('B',10,'Red Pepper','uncommon',2,2,True,SUM|AUT,"Ripens from the green sort and fetches more for having waited."),
 ('B',11,'Blueberry','exotic',2,3,True,SUM,"Three to a pick and picked three times. Dear seed, but the bush pays it back."),
 ('B',12,'Star Blossom','exotic',3,1,False,WIN,"Flowers in the dead of winter. Nothing else does, and the price says so."),
 ('B',13,'Bok Choy','common',1,1,False,SPR|WIN,"Five days, even in the cold. The winter farmer's carrot."),
]

B_ROWS = [16,17,18,19,20,21,23,25,26,27,29,30,31,32]
# the upper half of a crop too tall for its tile, drawn on the row above
TOPPERS = {('A',0):0, ('B',0):15, ('B',6):22, ('B',7):24, ('B',10):28}

SEED_SCENE = 'res://Scenes/World/Crop.tscn'
ICONS = 'res://Assets/Plants/PlantItemIcons.png'

def key(name):
    return re.sub(r'[^a-z0-9]+','_',name.lower()).strip('_')

def file_of(name):
    return name.replace(' ','')

def esc(t):
    return t.replace('\\','\\\\').replace('"','\\"')

made = []
for group, idx, name, rarity, dps, pcount, regrows, seasons, blurb in TABLE:
    mult, absorbs, vol = TIER[rarity]
    row = idx + 1 if group == 'A' else B_ROWS[idx]
    topper = TOPPERS.get((group, idx), -1)
    seed_col, prod_col = (0, 32) if group == 'A' else (64, 96)
    y = idx * 32

    days = 5 * dps
    gross = days * GOLD_PER_DAY * mult
    picks = 1
    if regrows:
        gross *= REGROW_LIFE
        picks = REGROW_PICKS
    base = max(5, round(gross / (pcount * picks)))
    seed_price = max(4, round(gross * SEED_SHARE))

    k, f = key(name), file_of(name)

    (CROPS / f'{f}.tres').write_text(f'''[gd_resource type="Resource" script_class="ItemData" format=3]

[ext_resource type="Script" path="res://Scripts/Items/ItemData.gd" id="1_script"]
[ext_resource type="Texture2D" path="{ICONS}" id="2_sheet"]

[sub_resource type="AtlasTexture" id="AtlasTexture_icon"]
atlas = ExtResource("2_sheet")
region = Rect2({prod_col}, {y}, 32, 32)
filter_clip = true

[resource]
script = ExtResource("1_script")
id = &"{k}"
display_name = "{name}"
icon = SubResource("AtlasTexture_icon")
action = &""
stack_size = 99
''', encoding='utf8', newline='\n')

    (CROPS / f'{f}Crop.tres').write_text(f'''[gd_resource type="Resource" script_class="CropData" format=3]

[ext_resource type="Script" path="res://Scripts/Items/CropData.gd" id="1_script"]
[ext_resource type="Resource" path="res://Assets/Crops/{f}.tres" id="2_produce"]

[resource]
script = ExtResource("1_script")
id = &"{k}"
display_name = "{name}"
sheet_row = {row}
topper_row = {topper}
stages = 6
seasons = {seasons}
days_per_stage = {dps}
needs_water = true
produce = ExtResource("2_produce")
produce_count = {pcount}
regrows = {str(regrows).lower()}
regrow_stage = 3
''', encoding='utf8', newline='\n')

    (CROPS / f'{f}Seeds.tres').write_text(f'''[gd_resource type="Resource" script_class="SeedData" format=3]

[ext_resource type="Script" path="res://Scripts/Items/SeedData.gd" id="1_script"]
[ext_resource type="Texture2D" path="{ICONS}" id="2_sheet"]
[ext_resource type="PackedScene" path="{SEED_SCENE}" id="3_scene"]
[ext_resource type="Resource" path="res://Assets/Crops/{f}Crop.tres" id="4_crop"]

[sub_resource type="AtlasTexture" id="AtlasTexture_icon"]
atlas = ExtResource("2_sheet")
region = Rect2({seed_col}, {y}, 32, 32)
filter_clip = true

[resource]
script = ExtResource("1_script")
id = &"{k}_seeds"
display_name = "{name} Seeds"
description = "{esc(blurb)}"
icon = SubResource("AtlasTexture_icon")
action = &""
stack_size = 99
scene = ExtResource("3_scene")
footprint = Vector2i(1, 1)
surface = 1
sort_lift = 16.0
recoverable = false
crop = ExtResource("4_crop")
''', encoding='utf8', newline='\n')

    def good(path, item, shelf, price, volatility, absorb, in_shop):
        path.write_text(f'''[gd_resource type="Resource" script_class="MarketGood" format=3]

[ext_resource type="Script" path="res://Scripts/Economy/MarketGood.gd" id="1_script"]
[ext_resource type="Resource" path="res://Assets/Crops/{item}.tres" id="2_item"]

[resource]
script = ExtResource("1_script")
item = ExtResource("2_item")
shelf = {shelf}
base_price = {price}
volatility = {volatility}
in_shop = {str(in_shop).lower()}
absorbs = {absorb}
''', encoding='utf8', newline='\n')

    good(MARKET / f'{f}.tres', f, 0, base, vol, absorbs, False)
    good(MARKET / f'{f}Seeds.tres', f'{f}Seeds', 0, seed_price, 0.06, 999.0, True)
    made.append((name, rarity, row, topper, days, pcount, regrows, seasons, seed_price, base))

names = {'1':'Spr','2':'Sum','4':'Aut','8':'Win'}
def seas(m):
    return '+'.join(n for b,n in [(1,'Spr'),(2,'Sum'),(4,'Aut'),(8,'Win')] if m & b)

print(f'{"crop":<14}{"tier":<10}{"row":>4}{"top":>5}{"days":>6}{"yld":>5}{"regrow":>8}  {"seasons":<16}{"seed":>6}{"sells":>7}')
for n,r,row,top,d,pc,rg,s,sp,bp in made:
    print(f'{n:<14}{r:<10}{row:>4}{top:>5}{d:>6}{pc:>5}{"yes" if rg else "-":>8}  {seas(s):<16}{sp:>6}{bp:>7}')
print(f'\n{len(made)} crops, {len(made)*5} files')
print('winter:', ', '.join(n for n,_,_,_,_,_,_,s,_,_ in made if s & 8))
