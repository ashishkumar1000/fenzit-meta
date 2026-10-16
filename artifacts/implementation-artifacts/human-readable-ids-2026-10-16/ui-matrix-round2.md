# UI test matrix — round 2 (50 on-device cases, 2026-10-16)

Device: Pixel 6 (1080×2400), owner session (Ayush / Business). Read-only bias: destructive dialogs opened but never confirmed. Coordinates = screenshot×1.2.

## Navigation & shell (N1–N8)
N1 tab cycle Home→Jobs→Customers→Account renders each header · N2 back from detail preserves list scope · N3 hw-back at top-level backgrounds app · N4 force-stop + relaunch keeps session · N5 rapid tab switching stable · N6 bell badge consistency Home vs Jobs · N7 leave tabs Pending↔All · N8 kill during loading → clean relaunch

## Home (N9–N14)
N9 metric cards match Jobs counts · N10 overdue strip = overdue badge · N11 action tiles with counts · N12 attendance tile navigates · N13 pull-to-refresh clean · N14 home clean after deep return

## Jobs list (N15–N22)
N15 Today empty state · N16 Overdue urgency rail · N17 History renders done/cancelled · N18 filter chips scroll · N19 Done filter narrows · N20 Upcoming empty state · N21 card tap target · N22 long name ellipsizes

## Job detail (N23–N30)
N23 header + back · N24 6-step progress · N25 edit sheet cancel · N26 Cancel-job visible (no confirm) · N27 Call/Directions · N28 technician section · N29 dual badges · N30 scroll bottom intact

## Customers (N31–N36)
N31 search "har" filters · N32 no-match state · N33 clear restores · N34 history chips/scroll · N35 detail back preserved · N36 add-customer cancel

## Technicians (N37–N41)
N37 long roster scroll stable · N38 badge states · N39 add-tech cancel · N40 row tap behavior · N41 avatar initials

## Notifications (N42–N45)
N42 list + mark-all present · N43 tap navigates · N44 filter tabs · N45 unread dots

## Attendance (N46–N50)
N46 Today grid · N47 Monthly view · N48 apply-on-behalf cancel · N49 Offices · N50 Settings
