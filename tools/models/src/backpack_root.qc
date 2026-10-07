$modelname "nyrp/bags/backpack_root.mdl"
$body body "backpack_root.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$sequence idle "backpack_root.smd" fps 30
$collisionmodel "backpack_phys.smd" { $mass 1 }
