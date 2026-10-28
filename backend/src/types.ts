
export type AttendanceEventType = "CHECK_IN" | "CHECK_OUT";

export interface AttendanceRecord {
  id: string;
  eventId: string;
  employeeId: string;
  type: AttendanceEventType;
  occurredAt: string;
  companyDate: string;
  latitude: number;
  longitude: number;
  status: "SYNCED";
}

export type LeaveType = "CASUAL" | "SICK";

export type LeaveStatus =
  | "PENDING"
  | "APPROVED"
  | "REJECTED";

export interface LeaveBalance {
  employeeId: string;
  casual: number;
  sick: number;
}

export interface LeaveRequest {
  id: string;
  employeeId: string;
  type: LeaveType;
  startDate: string;
  endDate: string;
  days: number;
  reason: string;
  status: LeaveStatus;
  createdAt: string;
}