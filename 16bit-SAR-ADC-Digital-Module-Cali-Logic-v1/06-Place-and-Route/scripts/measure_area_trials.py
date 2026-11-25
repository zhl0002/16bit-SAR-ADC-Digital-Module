"""Record physical closure and actual DEF dimensions for each compact run."""

import json
import re
import sys
from pathlib import Path


BASELINE_AREA = 423.92 * 423.20


def read(path):
    return path.read_text(errors='replace') if path.is_file() else ''


def find_number(text, pattern, cast=float):
    match = re.search(pattern, text, re.MULTILINE)
    return cast(match.group(1)) if match else None


def dimensions(def_text):
    scale = find_number(def_text, r'^UNITS DISTANCE MICRONS (\d+)', int)
    bounds = re.search(r'^DIEAREA\s+([^;]+);', def_text, re.MULTILINE)
    if scale is None or not bounds:
        return None, None
    points = re.findall(r'\(\s*(-?\d+)\s+(-?\d+)\s*\)', bounds.group(1))
    xs = [int(x) for x, _ in points]
    ys = [int(y) for _, y in points]
    return (max(xs) - min(xs)) / scale, (max(ys) - min(ys)) / scale


def measure(folder):
    reports = folder / 'reports/final'
    routes = read(reports / 'routes.rpt')
    lvs = read(reports / 'internal_lvs.rpt')
    pg = read(reports / 'pg_connectivity.rpt')
    qor = read(reports / 'qor.rpt')
    def_text = read(folder / 'output/cali_logic_routed.def')
    width, height = dimensions(def_text)
    area = width * height if width is not None else None
    status = read(folder / 'exit_status').strip()
    row = {
        'candidate': folder.name,
        'exit_status': int(status) if status else None,
        'width_um': width,
        'height_um': height,
        'area_um2': round(area, 4) if area is not None else None,
        'area_reduction_pct': round(100 * (1 - area / BASELINE_AREA), 4) if area is not None else None,
        'utilization': find_number(read(reports / 'utilization.rpt'), r'Utilization Ratio:\s+([\d.]+)'),
        'netlist_cells': find_number(qor, r'^Leaf Cell Count:\s+(\d+)', int),
        'netlist_area_um2': find_number(qor, r'Cell Area \(netlist\):\s+([\d.]+)'),
        'components': find_number(def_text, r'^COMPONENTS\s+(\d+)', int),
        'fillers': len(re.findall(r'^\s*-\s+\S+\s+FILL\d+\b', def_text, re.MULTILINE)),
        'open_nets': find_number(routes, r'Total number of open nets = (\d+)', int),
        'route_drc': find_number(routes, r'Total number of DRCs = (\d+)', int),
        'layout_legal': 'check_legality succeeded' in read(reports / 'legality.rpt'),
        'pg_drc_clean': 'No errors found.' in read(reports / 'pg_drc_console.rpt'),
        'pg_connected': (
            len(re.findall(r'Number of disjoint networks: 1(?:\D|$)', pg)) == 2
            and len(re.findall(r'Number of floating (?:std cells|terminals): 0(?:\D|$)', pg)) == 4
        ),
        'internal_lvs_clean': all(f'Total number of {item} is 0.' in lvs for item in (
            'short violations', 'open nets', 'floating route violations',
        )),
        'setup_ns': find_number(read(reports / 'setup.rpt'), r'slack \(\w+\)\s+([-\d.]+)'),
        'hold_ns': find_number(read(reports / 'hold.rpt'), r'slack \(\w+\)\s+([-\d.]+)'),
    }
    row['passes'] = (
        row['exit_status'] == 0 and area is not None
        and row['open_nets'] == row['route_drc'] == 0
        and all(row[key] for key in ('layout_legal', 'pg_drc_clean', 'pg_connected', 'internal_lvs_clean'))
        and row['setup_ns'] is not None and row['setup_ns'] >= 0
        and row['hold_ns'] is not None and row['hold_ns'] >= 0
    )
    return row


if __name__ == '__main__':
    print(json.dumps([measure(Path(folder)) for folder in sys.argv[1:]], indent=2))
