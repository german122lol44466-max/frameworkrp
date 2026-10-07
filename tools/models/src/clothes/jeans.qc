$modelname "nyrp/clothes/jeans.mdl"
$body body "jeans.smd"
$staticprop
$cdmaterials "models/nyrp/clothes/"
$surfaceprop "cloth"
$sequence idle "jeans.smd" fps 30
$collisionmodel "jeans.smd" { $concave $mass 1 }
