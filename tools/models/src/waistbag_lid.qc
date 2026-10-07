$modelname "nyrp/bags/waistbag_lid.mdl"
$body body "waistbag_lid.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$sequence idle "waistbag_lid.smd" fps 30
$collisionmodel "waistbag_phys.smd" { $mass 1 }
