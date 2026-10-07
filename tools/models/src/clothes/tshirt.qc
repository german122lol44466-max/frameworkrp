$modelname "nyrp/clothes/tshirt.mdl"
$body body "tshirt.smd"
$staticprop
$cdmaterials "models/nyrp/clothes/"
$surfaceprop "cloth"
$sequence idle "tshirt.smd" fps 30
$collisionmodel "tshirt.smd" { $concave $mass 1 }
