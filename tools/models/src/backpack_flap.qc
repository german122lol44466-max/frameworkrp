$modelname "nyrp/bags/backpack_flap.mdl"
$body body "backpack_flap.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$sequence idle "backpack_flap.smd" fps 30
$collisionmodel "backpack_phys.smd" { $mass 1 }
