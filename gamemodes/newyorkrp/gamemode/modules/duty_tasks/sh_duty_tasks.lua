--[[
	Занятия для служб на дежурстве (NW2Bool nyrp.onDuty).
	  NYPD: патрулирование по точкам (/patrol или служебный компьютер → «Задания»), за маршрут $60;
	        происшествия «подозрительная активность» — улика на месте, E 4 с — осмотр и отчёт, $40.
	  EMS:  вызовы к пострадавшим (nyrp_patient): E — осмотреть / перевязать / дефибриллятор, $70.
	  FDNY: обход гидрантов (/hydrants или компьютер), E 3 с у гидранта — проверено, за обход $50.
	  Все:  /dutycancel — отменить задание. Задание сбрасывается при конце дежурства, смене роли, смерти, выходе.
	Админ: /patrolpoint — точка патруля, /patrolpointdel — удалить ближайшую, /patrols — показать точки,
	       /dutyincident <police|medic> — вызвать происшествие сейчас.
]]
NYRP.DutyTasks = NYRP.DutyTasks or {}

if SERVER then
	util.AddNetworkString("nyrp.duty.task")         -- сервер → клиент: панель задания
	util.AddNetworkString("nyrp.duty.act")          -- клиент → сервер: взять / отменить задание
	util.AddNetworkString("nyrp.duty.patient")      -- сервер → клиент: меню пострадавшего
	util.AddNetworkString("nyrp.duty.patient.act")  -- клиент → сервер: действие с пострадавшим
end
