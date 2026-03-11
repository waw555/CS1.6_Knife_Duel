#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
//#include <cstrike>
#include <amxmisc>
//#include <csx>

#define PLUGIN "Knife Duel"
#define VERSION "1.0.0.0-28.09.2025"
#define AUTHOR "Alka/MS"
#define URL "www.masks-show.ru"
#define DESCRIPTION "Plugin for knife duel"

#pragma semicolon 1

#define CBASE_CURRWPN_ENT 373
#define OFFSET_ENT_TO_INDEX 43

new const g_szKnifeSound[] = "weapons/knife_hitwall1.wav";
new const g_szSpawnClassname[] = "info_player_deathmatch";

new Float:g_fHit[33];
new iHitCount[33];
new g_iChallenged, g_iChallenger;

new Float:g_vKnifeOrigin[2][3];
new bool:g_bInChallenge;
new bool:g_bProtect;
new g_iTimer;
new i_Counter = true;

enum _:max_cvars {
	CVAR_COUNT,
	CVAR_TIMER,
	CVAR_MAXDISTANCE,
	CVAR_PROTECTION,
	CVAR_ANNOUNCE,
	CVAR_RESET,
};
new g_Pcvar[max_cvars];

new g_iMaxPlayers;

public plugin_init() {
	
	register_plugin(PLUGIN, VERSION, AUTHOR, URL, DESCRIPTION);
	
	register_forward(FM_EmitSound, "fwd_EmitSound", 1);
	register_forward(FM_PlayerPreThink, "fwd_PlayerPreThink_post", 1);
	RegisterHam(Ham_Killed, "player", "fwd_Killed", 1);
	
	register_logevent("logevent_RoundEnd", 2, "1=Round_End", "1=Round_Draw");
	register_logevent("logevent_BombAction", 3, "2=Planted_The_Bomb");
	register_logevent("logevent_BombAction", 3, "2=Defused_The_Bomb");
	
	g_Pcvar[CVAR_COUNT] = register_cvar("kd_knifecount", "1");
	g_Pcvar[CVAR_TIMER] = register_cvar("kd_preparetime", "30");
	g_iTimer = get_pcvar_num(g_Pcvar[CVAR_TIMER]);
	g_Pcvar[CVAR_PROTECTION] = register_cvar("kd_protection", "1");
	g_Pcvar[CVAR_MAXDISTANCE] = register_cvar("kd_maxdistance", "99999");
	g_Pcvar[CVAR_ANNOUNCE] = register_cvar("kd_announce", "1");
	g_Pcvar[CVAR_RESET] = register_cvar("kd_resethp", "1");
	g_iMaxPlayers = get_maxplayers();
	register_event("RoundTime", "eNewRound", "bc");
	register_concmd("kd_forceduel", "cmdForceDuel", ADMIN_BAN, "- Запустить ножевую дуэль, если в любой команде остался 1 игрок");
}

public cmdForceDuel(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED;

	if(g_bInChallenge)
	{
		client_print(id, print_console, "[Knife Duel] Дуэль уже запущена.");
		return PLUGIN_HANDLED;
	}

	new iLoneT = get_single_alive_player(1);
	new iLoneCT = get_single_alive_player(2);

	if(!iLoneT && !iLoneCT)
	{
		client_print(id, print_console, "[Knife Duel] В командах должно остаться по одному игроку хотя бы в одной из сторон.");
		return PLUGIN_HANDLED;
	}

	new iChallenger = iLoneT ? iLoneT : iLoneCT;
	new iOpponent = get_opponent(3 - get_user_team(iChallenger));

	if(!is_user_alive(iChallenger) || !is_user_alive(iOpponent))
	{
		client_print(id, print_console, "[Knife Duel] Не удалось подобрать участников дуэли.");
		return PLUGIN_HANDLED;
	}

	g_iChallenger = iChallenger;
	g_iChallenged = iOpponent;
	g_bInChallenge = true;

	new szName[32], szOppName[32];
	get_user_name(iChallenger, szName, sizeof szName - 1);
	get_user_name(iOpponent, szOppName, sizeof szOppName - 1);

	client_print(0, print_chat, " [Knife Duel] Администратор принудительно запустил дуэль: %s vs %s.", szName, szOppName);
	fnStartDuel();
	client_print(id, print_console, "[Knife Duel] Принудительная дуэль запущена.");

	return PLUGIN_HANDLED;
}

public plugin_precache()
{
	precache_generic("sound/ms/knife_duel_menu.mp3");
	precache_generic("sound/ms/knife_duel_stop.mp3");
	precache_generic("sound/ms/knife_duel_start.mp3");
	register_forward(FM_Spawn, "fwd_Spawn", 1);
}

public client_disconnected(id)
{
	if((id == g_iChallenged) || (id == g_iChallenger))
	{
		g_bInChallenge = false;
		g_bProtect = false;
		show_menu(g_iChallenged, 0, "^n", 1);
		show_menu(g_iChallenger, 0, "^n", 1);
		remove_task('x');
		i_Counter = false;
	}
}

public fwd_Spawn(ent)
{
	if(!pev_valid(ent))
		return FMRES_IGNORED;
	
	static szClassname[32];
	pev(ent, pev_classname, szClassname, sizeof szClassname - 1);
	
	if(equal(szClassname, g_szSpawnClassname))
	{
		if(vec_null(g_vKnifeOrigin[0]))
		{
			pev(ent, pev_origin, g_vKnifeOrigin[0]);
		}
		else if(!vec_null(g_vKnifeOrigin[0]) && vec_null(g_vKnifeOrigin[1]))
		{
			static Float:vTmp[3];
			static Float:fDistance;
			pev(ent, pev_origin, vTmp);
			fDistance = vector_distance(g_vKnifeOrigin[0], vTmp);
			
			if(fDistance >= 300.0 && fDistance < 1200.0)
				g_vKnifeOrigin[1] = vTmp;
		}
	}
	return FMRES_IGNORED;
}

public fwd_EmitSound(id, channel, const sound[])
{
	if(!is_user_alive(id))
		return FMRES_IGNORED;
	
	if(!equal(sound, g_szKnifeSound))
		return FMRES_IGNORED;
	
	static Float:fGmTime;
	fGmTime = get_gametime();
	
	if((fGmTime - g_fHit[id]) >= 1.0)
	{
		iHitCount[id] = 0;
		g_fHit[id] = fGmTime;
	}
	++iHitCount[id];
	g_fHit[id] = fGmTime;
	
	if((iHitCount[id] >= get_pcvar_num(g_Pcvar[CVAR_COUNT])) && check_players() && !g_bInChallenge)
	{
		new iOpponent = get_opponent(3 - get_user_team(id));
		if(!iOpponent)
			return FMRES_IGNORED;
		
		fnChallenge(id, iOpponent);
		
		iHitCount[id] = 0;
	}
	return FMRES_IGNORED;
}

public fwd_PlayerPreThink_post(id)
{
	if(!is_user_alive(id) || !g_bInChallenge)
		return FMRES_IGNORED;
	
	static iWpn;
	iWpn = get_pdata_cbase(id, CBASE_CURRWPN_ENT);
	
	if(pev_valid(iWpn))
	{
		if(get_pdata_int(iWpn, OFFSET_ENT_TO_INDEX) != CSW_KNIFE)
			engclient_cmd(id, "weapon_knife");
	}
	
	static iOpponent;
	if(id == g_iChallenged)
		iOpponent = g_iChallenger;
	else
		iOpponent = g_iChallenged;
	
	if(!is_user_connected(iOpponent))
		return FMRES_IGNORED;
	
	if((fm_get_entity_distance(id, iOpponent) >= get_pcvar_float(g_Pcvar[CVAR_MAXDISTANCE])) && g_bProtect)
	{
		static Float:vVel[3];
		fm_get_speed_vector2(id, iOpponent, 100.0, vVel);
		
		set_pev(id, pev_velocity, vVel);
	}
	return FMRES_IGNORED;
}

public fwd_Killed(id, idattacker, shouldgib)
{
	if(!get_pcvar_num(g_Pcvar[CVAR_ANNOUNCE]))
		return HAM_IGNORED;
	
	if(check_players())
	{
		for(new i = 0 ; i <= g_iMaxPlayers ; i++)
		{
			if(!is_user_alive(i))
				continue;
			
			client_print(i, print_chat, "Чтобы вызвать игрока на дуль, режь стену %d раз.", get_pcvar_num(g_Pcvar[CVAR_COUNT]));
		}
	}
	return HAM_IGNORED;
}

public fnChallenge(id, opponent)
{
	if(i_Counter){
		new szName[32], szOppName[32];
		get_user_name(id, szName, sizeof szName - 1); //Определяет имя 1 игрока
		get_user_name(opponent, szOppName, sizeof szOppName - 1); // Определяет имя 2 игрока
		
		new szTitle[128];
		formatex(szTitle, sizeof szTitle - 1, "\r%s \y Вызывает вас на дуель", szName);
		client_cmd(0,"mp3 play sound/ms/knife_duel_menu");
		
		new sMenu = menu_create(szTitle, "Menu_Main_Handler");
		menu_additem(sMenu, "Согласен", "1", 0, -1);
		menu_additem(sMenu, "Не согласен", "2", 0, -1);
		
		menu_setprop(sMenu, MPROP_EXIT, MEXIT_NEVER);
		menu_display(opponent, sMenu, 0);
		
		g_iTimer = get_pcvar_num(g_Pcvar[CVAR_TIMER]);
		
		client_print(0, print_chat, " %s вызвал на дуель на ножах %s .", szName, szOppName);
		
		g_iChallenger = id;
		g_iChallenged = opponent;
		g_bInChallenge = true;
	}
}

public Menu_Main_Handler(id, menu, item)
{
	if(!is_user_connected(id))
		return 0;

	if(item < 0)
	{
		menu_destroy(menu);
		return 0;
	}
	
	new szData[6], iAccess, iCallBack;
	menu_item_getinfo(menu, item, iAccess, szData, sizeof szData - 1, _, _, iCallBack);
	
	new iKey = str_to_num(szData);
	
	new szName[32];
	get_user_name(id, szName, sizeof szName - 1);
	
	switch(iKey)
	{
		case 1:
		{
			client_print(0, print_chat, " %s принял дуель на ножах", szName);
			fnStartDuel();
			server_cmd("amx_throwknives 0");
			
		}
		case 2:
		{
			client_print(0, print_chat, " %s отказался от дуели на ножах!", szName);
			client_cmd(0,"mp3 play sound/ms/knife_duel_stop");
			g_bInChallenge = false;
			server_cmd("amx_throwknives 1");
			i_Counter = false;
		}
	}

	menu_destroy(menu);
	return 1;
}	

public fnStartDuel()
{
	if(!is_user_connected(g_iChallenged) || !is_user_connected(g_iChallenger))
		return;
	
	engfunc(EngFunc_SetOrigin, g_iChallenged, g_vKnifeOrigin[0]);
	engfunc(EngFunc_SetOrigin, g_iChallenger, g_vKnifeOrigin[1]);
	
	fm_entity_set_aim(g_iChallenged, g_iChallenger, 0);
	fm_entity_set_aim(g_iChallenger, g_iChallenged, 0);
	
	fm_set_user_godmode(g_iChallenged, 0);
	fm_set_user_godmode(g_iChallenger, 0);
	
	if(get_pcvar_num(g_Pcvar[CVAR_RESET]))
	{
		set_pev(g_iChallenged, pev_health, 200.0);
		set_pev(g_iChallenger, pev_health, 200.0);
	}
	
	set_task(1.0, "taskDuelThink", 'x', "", 0, "b", 0);
	client_cmd(0,"mp3 play sound/ms/knife_duel_start");
	server_cmd("amx_throwknives 0");
	
	if(get_pcvar_num(g_Pcvar[CVAR_PROTECTION]))
		g_bProtect = true;
}

public taskDuelThink(id, opponent)
{
	if(g_iTimer > 0)
	{
		set_hudmessage(255, 100, 0, -1.0, 0.3, 0, 6.0, 1.0, 0.1, 0.9, 1);
		show_hudmessage(0, "У вас осталось: %d сек.", g_iTimer--);
		}
	
	else
	{
		set_hudmessage(255, 100, 0, -1.0, 0.3, 0, 6.0, 1.0, 0.1, 0.5, 1);
		show_hudmessage(0, "Вы не успели вовремя!");
		
		g_iTimer = get_pcvar_num(g_Pcvar[CVAR_TIMER]);
		remove_task('x');
		g_bInChallenge = false;
		g_bProtect = false;
		if(is_user_alive(g_iChallenged)) user_kill(g_iChallenged);
		if( is_user_alive(g_iChallenger))user_kill(g_iChallenger);
		//client_cmd(0, "kill");
		i_Counter = true;

		for(new i = 1 ; i <= g_iMaxPlayers ; i++)
		{
			if(!is_user_alive(i))
				continue;
			
			fm_set_user_godmode(i, 0);
		}
	}
}


public logevent_RoundEnd()
{
	g_bInChallenge = false;
	g_bProtect = false;
	remove_task('x');
	server_cmd("amx_throwknives 1");
	show_menu(g_iChallenged, 0, "^n", 1);
	show_menu(g_iChallenger, 0, "^n", 1);
	client_cmd(0,"mp3 stop");
}

stock fm_entity_set_aim(id, ent, bone = 0)
{
	if(!is_user_connected(id) || !pev_valid(ent))
		return 0;
	
	new Float:vOrigin[3];
	pev(ent, pev_origin, vOrigin);
	
	new Float:vEntOrigin[3], Float:vAngles[3];
	
	if(bone)
		engfunc(EngFunc_GetBonePosition, id, bone, vEntOrigin, vAngles);
	else
		pev(id, pev_origin, vEntOrigin);
	
	vOrigin[0] -= vEntOrigin[0];
	vOrigin[1] -= vEntOrigin[1];
	vOrigin[2] -= vEntOrigin[2];
	
	new Float:v_length;
	v_length = vector_length(vOrigin);
	if(v_length <= 0.0)
		return 0;
	
	new Float:vAimVector[3];
	vAimVector[0] = vOrigin[0] / v_length;
	vAimVector[1] = vOrigin[1] / v_length;
	vAimVector[2] = vOrigin[2] / v_length;
	
	new Float:vNewAngles[3];
	vector_to_angle(vAimVector, vNewAngles);
	
	vNewAngles[0] *= -1;
	
	if(vNewAngles[1] > 180.0) vNewAngles[1] -= 360;
	if(vNewAngles[1] < -180.0) vNewAngles[1] += 360;
	if(vNewAngles[1] == 180.0 || vNewAngles[1] == -180.0) vNewAngles[1] = -179.9;
	
	set_pev(id, pev_angles, vNewAngles);
	set_pev(id, pev_fixangle, 1);
	
	return 1;
}

stock vec_null(Float:vec[3])
{
	if(!vec[0] && !vec[1] && !vec[2])
		return 1;
	
	return 0;
}

stock bool:check_players()
{
	new iNum[2];
	for(new i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_alive(i))
			continue;
		
		if(get_user_team(i) == 1)
			++iNum[0];
		else if(get_user_team(i) == 2)
			++iNum[1];
	}
	if((iNum[0] == 1) && (iNum[1] == 1))
		return true;
	
	return false;
}

stock get_single_alive_player(team)
{
	new iFound;

	for(new i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_alive(i))
			continue;

		if(get_user_team(i) != team)
			continue;

		if(iFound)
			return 0;

		iFound = i;
	}

	return iFound;
}

stock get_opponent(team)
{
	for(new i = 1 ; i <= g_iMaxPlayers ; i++)
	{
		if(!is_user_alive(i))
			continue;
		
		if(get_user_team(i) == team)
			return i;
	}
	return 0;
}

stock fm_set_user_godmode(index, godmode = 0)
{
	set_pev(index, pev_takedamage, godmode == 1 ? DAMAGE_NO : DAMAGE_AIM);
	return 1;
}

stock fm_get_speed_vector2(ent1, ent2, Float:speed, Float:new_velocity[3])
{
	if(!pev_valid(ent1) || !pev_valid(ent2))
		return 0;
	
	static Float:vOrigin1[3];
	pev(ent1, pev_origin, vOrigin1);
	static Float:vOrigin2[3];
	pev(ent2, pev_origin, vOrigin2);
	
	new_velocity[0] = vOrigin2[0] - vOrigin1[0];
	new_velocity[1] = vOrigin2[1] - vOrigin1[1];
	new_velocity[2] = vOrigin2[2] - vOrigin1[2];

	new Float:fVectorLength = (new_velocity[0] * new_velocity[0] + new_velocity[1] * new_velocity[1] + new_velocity[2] * new_velocity[2]);
	if(fVectorLength <= 0.0)
		return 0;

	new Float:fNum = floatsqroot(speed * speed / fVectorLength);
	new_velocity[0] *= fNum;
	new_velocity[1] *= fNum;
	new_velocity[2] *= fNum;
	
	return 1;
}

stock Float:fm_get_entity_distance(ent1, ent2)
{
	if(!pev_valid(ent1) || !pev_valid(ent2))
		return 0.0;
	
	static Float:vOrigin1[3];
	pev(ent1, pev_origin, vOrigin1);
	static Float:vOrigin2[3];
	pev(ent2, pev_origin, vOrigin2);
	return vector_distance(vOrigin1, vOrigin2);
}

public logevent_BombAction()
{
	i_Counter = false;
}

public eNewRound()
{
	i_Counter = true;
}
