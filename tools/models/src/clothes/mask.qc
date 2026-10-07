$modelname "nyrp/clothes/mask.mdl"
$body body "mask.smd"
$staticprop
$cdmaterials "models/nyrp/clothes/"
$surfaceprop "cloth"
$sequence idle "mask.smd" fps 30
$collisionmodel "mask.smd" { $concave $mass 1 }
