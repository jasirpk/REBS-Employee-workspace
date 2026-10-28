import type { AttendanceRecord } from "./types.js";
import express from "express";
import cors from "cors";

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
    "duplicate"
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

type MockScenario =
  | "normal"
  | "slow"
  | "error500"
  | "timeout_before"
  | "timeout_after"
  | "duplicate";

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

app.listen(PORT, () => {
  console.log(`REBS API running at http://localhost:${PORT}`);
});