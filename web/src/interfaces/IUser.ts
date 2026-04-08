import type { PlayerData } from "./IPlayerData";

export type JobType = 'leo' | 'ems' | 'doj' | 'civilian';

export interface DepartmentLabels {
	singular: string;
	plural: string;
}

export interface AuthUpdateData {
	playerData?: PlayerData;
	isLEO?: boolean;
	onDuty?: boolean;
	authorized?: boolean;
	permissions?: string[];
	isBoss?: boolean;
	jobType?: JobType;
	isCivilian?: boolean;
	departmentLabels?: DepartmentLabels;
}
