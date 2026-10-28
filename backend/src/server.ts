import express from "express";
import cors from "cors";
import type {
  AttendanceRecord,
  LeaveBalance,
  LeaveRequest,
  LeaveType
} from "./types.js";

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

// helper-method - It calculates the distance between two geographic coordinates in metres

function distanceInMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const earthRadius = 6_371_000;
  const toRadians = (degrees: number) => degrees * Math.PI / 180;

  const latitudeDifference = toRadians(lat2 - lat1);
  const longitudeDifference = toRadians(lon2 - lon1);

  const a =
    Math.sin(latitudeDifference / 2) ** 2 +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(longitudeDifference / 2) ** 2;

  return earthRadius * 2 * Math.atan2(
    Math.sqrt(a),
    Math.sqrt(1 - a)
  );
}

app.get("/api/health", (_req, res) => {
  res.status(200).json({
    status: "ok",
    message: "REBS Employee Workspace API is running"
  });
});

app.post("/api/__admin/scenario", (req, res) => {
  const { scenario } = req.body ?? {};

  const allowedScenarios: MockScenario[] = [
    "normal",
    "slow",
    "error500",
    "timeout_before",
    "timeout_after",
    "duplicate",
    "leave_rejection",
  ];

  if (
    typeof scenario !== "string" ||
    !allowedScenarios.includes(scenario as MockScenario)
  ) {
    res.status(400).json({
      code: "INVALID_SCENARIO",
      message: "Unsupported mock scenario",
      allowedScenarios
    });
    return;
  }

  activeScenario = scenario as MockScenario;

  res.status(200).json({
    message: "Mock scenario updated",
    scenario: activeScenario
  });
});

app.post("/api/__admin/reset", (_req, res) => {
  attendanceRecords.splice(
    0,
    attendanceRecords.length,
    ...structuredClone(seedAttendanceRecords)
  );

  activeScenario = "normal";

  res.status(200).json({
    message: "Mock API reset successfully",
    scenario: activeScenario
  });
});


const employee = {
  id: "EMP001",
  name: "Alex Johnson",
  department: "Engineering",
  office: {
    latitude: 12.9716,
    longitude: 77.5946,
    radiusMeters: 200
  },
  timezone: "Asia/Kolkata"
};


const attendanceRecords: AttendanceRecord[] = [
  {
    id: "ATT001",
    eventId: "evt-seed-001",
    employeeId: employee.id,
    type: "CHECK_IN",
    occurredAt: "2026-10-27T03:30:00.000Z",
    companyDate: "2026-10-27",
    latitude: 12.9716,
    longitude: 77.5946,
    status: "SYNCED"
  },
  {
    id: "ATT002",
    eventId: "evt-seed-002",
    employeeId: employee.id,
    type: "CHECK_OUT",
    occurredAt: "2026-10-27T12:30:00.000Z",
    companyDate: "2026-10-27",
    latitude: 12.9716,
    longitude: 77.5946,
    status: "SYNCED"
  }
];

const leaveBalance: LeaveBalance = {
  employeeId: employee.id,
  casual: 8,
  sick: 6
};

const leaveRequests: LeaveRequest[] = [
  {
    id: "LEAVE001",
    employeeId: employee.id,
    type: "CASUAL",
    startDate: "2026-10-20",
    endDate: "2026-10-21",
    days: 2,
    reason: "Personal family commitments",
    status: "APPROVED",
    createdAt: "2026-10-10T09:00:00.000Z"
  }
];

type MockScenario =
  | "normal"
  | "slow"
  | "error500"
  | "timeout_before"
  | "timeout_after"
  | "duplicate"
  | "leave_rejection";

let activeScenario: MockScenario = "normal";

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

const seedAttendanceRecords: AttendanceRecord[] =
  structuredClone(attendanceRecords);


app.get("/api/employee/me", (_req, res) => {
  res.status(200).json(employee);
});


app.get("/api/attendance", (req, res) => {
  const month = req.query.month;

  if (
    typeof month !== "string" ||
    !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)
  ) {
    res.status(400).json({
      code: "INVALID_MONTH",
      message: "month must use YYYY-MM format"
    });
    return;
  }

  const records = attendanceRecords
    .filter((record) => record.companyDate.startsWith(month))
    .sort((a, b) => {
      return b.occurredAt.localeCompare(a.occurredAt);
    });

  res.status(200).json({
    month,
    records
  });
});


app.post("/api/attendance/events", async (req, res) => {
  const scenario = activeScenario;

  if (scenario === "slow") {
    await delay(3000);
  }

  if (scenario === "error500") {
    res.status(500).json({
      code: "MOCK_SERVER_ERROR",
      message: "Simulated internal server error"
    });
    return;
  }

  if (scenario === "timeout_before") {
    await delay(10000);

    if (!res.destroyed) {
      res.status(504).json({
        code: "MOCK_TIMEOUT_BEFORE_PROCESSING",
        message: "The event was not processed"
      });
    }

    return;
  }

  if (scenario === "duplicate") {
    res.status(409).json({
      code: "ATTENDANCE_ALREADY_EXISTS",
      message: "Simulated duplicate attendance conflict"
    });
    return;
  }

    const {
    eventId,
    type,
    occurredAt,
    companyDate,
    latitude,
    longitude,
    accuracyMeters
  } = req.body ?? {};

  // 1. Validate the request fields.
  if (
    typeof eventId !== "string" ||
    eventId.trim().length === 0 ||
    !["CHECK_IN", "CHECK_OUT"].includes(type) ||
    typeof occurredAt !== "string" ||
    typeof companyDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(companyDate) ||
    !Number.isFinite(Date.parse(occurredAt)) ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    !Number.isFinite(accuracyMeters) ||
    accuracyMeters < 0
  ) {
    res.status(400).json({
      code: "INVALID_ATTENDANCE_EVENT",
      message: "Attendance event fields are invalid"
    });
    return;
  }

  // 2. Check idempotency before attendance conflicts.
  const existingEvent = attendanceRecords.find(
    (record) => record.eventId === eventId
  );

  if (existingEvent) {
    const samePayload =
      existingEvent.type === type &&
      existingEvent.occurredAt === occurredAt &&
      existingEvent.companyDate === companyDate &&
      existingEvent.latitude === latitude &&
      existingEvent.longitude === longitude;

    if (!samePayload) {
      res.status(409).json({
        code: "IDEMPOTENCY_KEY_REUSED",
        message: "This event ID was already used for another payload"
      });
      return;
    }

    res.status(200).json(existingEvent);
    return;
  }

  // 3. Validate that the supplied date matches company time.
  const parsedDate = new Date(occurredAt);
  const companyDateFromTimestamp = new Intl.DateTimeFormat(
    "en-CA",
    {
      timeZone: employee.timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }
  ).format(parsedDate);

  if (companyDateFromTimestamp !== companyDate) {
    res.status(422).json({
      code: "COMPANY_DATE_MISMATCH",
      message: "The event date does not match the company timezone"
    });
    return;
  }

  // 4. Enforce the office geofence on the server.
  const distance = distanceInMeters(
    latitude,
    longitude,
    employee.office.latitude,
    employee.office.longitude
  );

  if (distance > employee.office.radiusMeters) {
    res.status(422).json({
      code: "OUTSIDE_GEOFENCE",
      message: "You must be within 200 metres of the office",
      distanceMeters: Math.round(distance)
    });
    return;
  }

  // 5. Find existing attendance actions for this company day.
  const dayRecords = attendanceRecords.filter(
    (record) => record.companyDate === companyDate
  );

  const checkIn = dayRecords.find(
    (record) => record.type === "CHECK_IN"
  );

  const checkOut = dayRecords.find(
    (record) => record.type === "CHECK_OUT"
  );

  if (type === "CHECK_IN" && checkIn) {
    res.status(409).json({
      code: "ATTENDANCE_ALREADY_EXISTS",
      message: "A check-in already exists for this day"
    });
    return;
  }

  if (type === "CHECK_OUT" && !checkIn) {
    res.status(422).json({
      code: "CHECK_IN_REQUIRED",
      message: "Check-in is required before check-out"
    });
    return;
  }

  if (type === "CHECK_OUT" && checkOut) {
    res.status(409).json({
      code: "ATTENDANCE_ALREADY_EXISTS",
      message: "A check-out already exists for this day"
    });
    return;
  }

  // 6. Persist the accepted event in the mock store.
  const record: AttendanceRecord = {
    id: `ATT${Date.now()}`,
    eventId,
    employeeId: employee.id,
    type,
    occurredAt: parsedDate.toISOString(),
    companyDate,
    latitude,
    longitude,
    status: "SYNCED"
  };

attendanceRecords.push(record);

if (scenario === "timeout_after") {
  // The event is saved, but the response arrives too late
  // for a client with a shorter request timeout.
  await delay(10000);

  if (res.destroyed) {
    return;
  }
}

res.status(201).json(record);
});

app.get("/api/leave/balance", (_req, res) => {
  res.status(200).json(leaveBalance);
});

app.get("/api/leave/requests", (_req, res) => {
  const requests = leaveRequests
    .filter((request) => request.employeeId === employee.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  res.status(200).json({ requests });
});

app.post("/api/leave/requests", (req, res) => {
  const { type, startDate, endDate, reason } = req.body ?? {};

  // 1. Validate fields.
  if (
    !["CASUAL", "SICK"].includes(type) ||
    typeof startDate !== "string" ||
    typeof endDate !== "string" ||
    typeof reason !== "string"
  ) {
    res.status(400).json({
      code: "INVALID_LEAVE_REQUEST",
      message: "Leave request fields are invalid"
    });
    return;
  }

  // Strictly validate real calendar dates in YYYY-MM-DD format.
  const isValidDate = (value: string): boolean => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;

    const date = new Date(`${value}T00:00:00.000Z`);
    return !Number.isNaN(date.getTime()) &&
      date.toISOString().slice(0, 10) === value;
  };

  if (!isValidDate(startDate) || !isValidDate(endDate)) {
    res.status(400).json({
      code: "INVALID_DATE",
      message: "Dates must be valid YYYY-MM-DD calendar dates"
    });
    return;
  }

  // 2. Determine today's date in the company timezone.
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: employee.timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).format(new Date());

  if (startDate < today) {
    res.status(422).json({
      code: "START_DATE_IN_PAST",
      message: "Leave start date cannot be before today"
    });
    return;
  }

  if (endDate < startDate) {
    res.status(422).json({
      code: "INVALID_DATE_RANGE",
      message: "End date must be on or after start date"
    });
    return;
  }

  // Count non-whitespace characters in the reason.
  if (reason.replace(/\s/g, "").length < 10) {
    res.status(422).json({
      code: "REASON_TOO_SHORT",
      message: "Reason must contain at least 10 non-whitespace characters"
    });
    return;
  }

  // Repeatable simulated server-side rejection.
  if (activeScenario === "leave_rejection") {
    res.status(422).json({
      code: "LEAVE_VALIDATION_REJECTED",
      message: "Simulated leave validation rejection"
    });
    return;
  }

  // Inclusive calendar-day count, including weekends and holidays.
  const start = new Date(`${startDate}T00:00:00.000Z`);
  const end = new Date(`${endDate}T00:00:00.000Z`);
  const days =
    Math.round((end.getTime() - start.getTime()) / 86_400_000) + 1;

  const leaveType = type as LeaveType;
  const availableDays =
    leaveType === "CASUAL" ? leaveBalance.casual : leaveBalance.sick;

  if (days > availableDays) {
    res.status(422).json({
      code: "INSUFFICIENT_LEAVE_BALANCE",
      message: `Requested ${days} days, but only ${availableDays} days are available`
    });
    return;
  }

  // Pending and approved requests reserve their dates.
  const overlaps = leaveRequests.some((request) => {
    if (request.status !== "PENDING" && request.status !== "APPROVED") {
      return false;
    }

    return startDate <= request.endDate && endDate >= request.startDate;
  });

  if (overlaps) {
    res.status(422).json({
      code: "LEAVE_DATE_OVERLAP",
      message: "Dates overlap an existing pending or approved leave request"
    });
    return;
  }

  // Save the accepted request in the mock store.
  const request: LeaveRequest = {
    id: `LEAVE${Date.now()}`,
    employeeId: employee.id,
    type: leaveType,
    startDate,
    endDate,
    days,
    reason: reason.trim(),
    status: "PENDING",
    createdAt: new Date().toISOString()
  };

  leaveRequests.push(request);

  res.status(201).json(request);
});

app.listen(PORT, () => {
  console.log(`REBS API running at http://localhost:${PORT}`);
});