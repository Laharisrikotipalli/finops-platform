import sys, json

data = json.load(sys.stdin)
mode = sys.argv[1] if len(sys.argv) > 1 else "csv"

if mode == "csv":
    for day_entry in data.get("data", []):
        if not day_entry:
            continue
        for team, v in day_entry.items():
            print(",".join(str(x) for x in [
                team,
                v.get("start", "")[:10],
                round(v.get("cpuCost", 0), 4),
                round(v.get("ramCost", 0), 4),
                round(v.get("pvCost", 0), 4),
                round(v.get("networkCost", 0), 4),
                round(v.get("loadBalancerCost", 0), 4),
                round(v.get("sharedCost", 0), 4),
                round(v.get("totalCost", 0), 4),
                round(v.get("cpuEfficiency", 0) * 100, 1),
                round(v.get("ramEfficiency", 0) * 100, 1),
            ]))
else:
    totals = {}
    for day_entry in data.get("data", []):
        if not day_entry:
            continue
        for team, v in day_entry.items():
            totals[team] = totals.get(team, 0) + v.get("totalCost", 0)
    for team, total in sorted(totals.items()):
        print("  {:20s}: ${:.4f}".format(team, total))
    print("  {:20s}: ${:.4f}".format("GRAND TOTAL", sum(totals.values())))