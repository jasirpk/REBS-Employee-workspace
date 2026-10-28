
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
