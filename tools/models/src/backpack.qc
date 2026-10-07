$modelname "nyrp/bags/backpack.mdl"
$body body "backpack_ref.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$illumposition 0 0 0
$sequence idle "backpack_idle.smd" fps 30 loop
$sequence open "backpack_open.smd" fps 30
$sequence close "backpack_close.smd" fps 30
$collisionmodel "backpack_phys.smd"
{
	$mass 5
}
