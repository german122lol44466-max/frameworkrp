$modelname "nyrp/bags/waistbag.mdl"
$body body "waistbag_ref.smd"
$cdmaterials "models/nyrp/bags/"
$surfaceprop "cloth"
$illumposition 0 0 0
$sequence idle "waistbag_idle.smd" fps 30 loop
$sequence open "waistbag_open.smd" fps 30
$sequence close "waistbag_close.smd" fps 30
$collisionmodel "waistbag_phys.smd"
{
	$mass 2
}
