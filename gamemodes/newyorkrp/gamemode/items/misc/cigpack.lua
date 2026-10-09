ITEM.Name = "Сигареты «Liberty Lights»"
ITEM.Description = "Пачка лёгких сигарет. ПКМ → «Взять в рот», затем подкурите зажигалкой (ЛКМ)."
ITEM.Model = "models/nyrp/props/w_cigpack.mdl"
ITEM.Uses = 20                     -- сигарет в пачке
ITEM.UseText = "Взять сигарету в рот"
ITEM.Buffs = { { "Пока курите: спокойствие, выносливость восстанавливается быстрее", true },
	{ "После: −5 к жажде, −2 к здоровью, может пробить кашель", false } }
ITEM.Icon = { Angle = Angle(10, 200, 0), Zoom = 0.85 }
ITEM.OnUse = function(ply) return NYRP.Smoking.PutInMouth(ply) end
