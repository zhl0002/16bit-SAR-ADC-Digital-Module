#!/usr/bin/env python3
"""Prepare a serial replay of the TestMAX STIL emitted for cali_logic."""

from pathlib import Path
import argparse
import re


TOP = 'cali_logic'
TB = 'tb_cali_logic_stuck'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def group(text, name):
    match = re.search(rf'(?m)^\s*"{name}"\s*=\s*\x27([^\x27]+)\x27', text)
    require(match, f'Missing signal group {name}')
    return re.findall(r'"([^"\r\n]+)"', match[1])


def decode(value, width, symbols):
    value = re.sub(r'\\r(\d+)\s+([A-Z01])', lambda m: int(m[1]) * m[2], value)
    value = ''.join(value.split())
    require(len(value) == width and set(value) <= set(symbols),
            f'Unsupported vector of width {len(value)} (expected {width}): {value[:48]}')
    return value


def vector_fields(body):
    fields = {}
    for item in body.split(';'):
        if not item.strip():
            continue
        match = re.fullmatch(r'\s*"(\w+)"\s*=\s*(\S[\s\S]*)', item)
        require(match and match[1] not in fields, f'Unexpected vector assignment: {item[:48]}')
        fields[match[1]] = match[2]
    return fields


def parse(text):
    inputs = group(text, '_pi')
    outputs = group(text, '_po')
    require(len(inputs) == len(set(inputs)) == 12 and len(outputs) == len(set(outputs)) == 123,
            'Unexpected input or output group width')
    require(group(text, '_clk') == ['clk_i', 'rst_ni'], 'Unsupported scan clock group')
    require(group(text, '_si') == ['scan_in'] and group(text, '_so') == ['scan_out'],
            'Unsupported scan port group')

    chain = re.findall(r'ScanChain\s+"([^"\r\n]+)"\s*\{\s*ScanLength\s+(\d+)\s*;', text)
    require(len(chain) == 1 and chain[0] == ('scan_chain_0', '584'), 'Expected a single 584-cell scan chain')
    require('ScanInversion 0;' in text, 'Expected a non-inverted scan chain')
    length = int(chain[0][1])

    compact = re.sub(r'\s+', '', text)
    for signature in (
        "Period'100ns';", '"clk_i"{P{\'0ns\'D;\'45ns\'U;\'55ns\'D;}}',
        '"rst_ni"{P{\'0ns\'U;\'45ns\'D;\'55ns\'U;}}',
        "'40ns'H;", "'40ns'L;",
        '"Internal_scan_pre_shift":V{"scan_en"=1;}', 'V{"_clk"=P1;"_si"=#;"_so"=#;}',
        'V{"clk_i"=0;"rst_ni"=1;}V{}',
    ):
        require(signature in compact, f'Unrecognized STIL protocol feature: {signature}')
    periods = set(re.findall(r"Period\s+'([^']+)'", text))
    require(periods == {'100ns'}, f'Expected uniform 100 ns timing, got {periods}')

    start = re.search(r'(?m)^Pattern "_pattern_" \{', text)
    end = re.search(r'(?m)^}\s*\n\s*// Patterns reference \d+ V statements, generating (\d+) test cycles\s*$', text)
    require(start and end and end.start() > start.end(), 'Unsupported pattern block or missing cycle total')
    data = text[start.end():end.start()]
    data = re.sub(r'Ann\s*\{\*.*?\*\}', '', data, flags=re.S)
    head = re.match(r'\s*W "_multiclock_capture_WFT_";\s*"precondition all Signals":\s*C\s*\{([^{}]+)\}\s*Macro "test_setup";', data)
    require(head, 'Unexpected pattern initialization')
    initial = vector_fields(head[1])
    require(decode(initial['_pi'], len(inputs), '0') == '0' * len(inputs), 'Unexpected input initialization')
    require(decode(initial['_po'], len(outputs), 'X') == 'X' * len(outputs), 'Unexpected output initialization')

    data = data[head.end():]
    calls = []
    call_pattern = re.compile(r'\s*(?:"([^"]+)"\s*:\s*)?Call\s+"([^"]+)"\s*\{([^{}]*)\}', re.S)
    while data.strip():
        match = call_pattern.match(data)
        require(match, f'Unsupported STIL statement: {data[:65]}')
        calls.append((match[1], match[2], vector_fields(match[3])))
        data = data[match.end():]

    captures = (len(calls) - 1) // 2
    require(captures > 0 and len(calls) == 2 * captures + 1, 'Expected alternating scans and captures and final unload')
    prior_scan_in = '0'
    test_cycles = 2
    expected_checks = 0
    statements = []
    for index, (label, title, fields) in enumerate(calls):
        pattern = index // 2
        if index % 2 == 0:
            require(title == 'load_unload', 'Expected load_unload')
            expect_label = f'end {captures - 1} unload' if pattern == captures else f'pattern {pattern}'
            require(label == expect_label, f'Unexpected scan label {label}')
            required_fields = ({'scan_in'} if pattern == 0 else
                               {'scan_out'} if pattern == captures else {'scan_in', 'scan_out'})
            require(set(fields) == required_fields, f'Unexpected scan fields for {label}')
            drive = decode(fields.get('scan_in', prior_scan_in * length), length, '01')
            expect = decode(fields.get('scan_out', 'X' * length), length, 'HLX')
            prior_scan_in = drive[-1]
            expected_checks += length - expect.count('X')
            test_cycles += length + 1
            statements.append(f"    shift({length}'b{drive}, {length}'b{logic_bits(expect)}, {pattern});")
        else:
            require(label is None and title == 'multiclock_capture' and set(fields) == {'_pi', '_po'},
                    'Unexpected capture procedure')
            pi = decode(fields['_pi'], len(inputs), '01P')
            po = decode(fields['_po'], len(outputs), 'HLX')
            clk, rst = inputs.index('clk_i'), inputs.index('rst_ni')
            require(all(v != 'P' or i in (clk, rst) for i, v in enumerate(pi)), 'Unexpected pulse on a data pin')
            pulse_clk = int(pi[clk] == 'P')
            pulse_reset = int(pi[rst] == 'P')
            drive = ''.join(('1' if i == rst else '0') if val == 'P' else val for i, val in enumerate(pi))
            expected_checks += len(outputs) - po.count('X')
            test_cycles += 1
            statements.append(f"    capture({len(inputs)}'b{drive}, 1'b{pulse_clk}, 1'b{pulse_reset},"
                              f" {len(outputs)}'b{logic_bits(po)}, {pattern});")

    require(test_cycles == int(end[1]), f'Replay cycles {test_cycles} disagree with STIL total {end[1]}')
    require(expected_checks > 0, 'No expected values to compare')
    return inputs, outputs, statements, captures, test_cycles, expected_checks


def logic_bits(text):
    return text.translate(str.maketrans('HLX', '10x'))


def declarations(pins, kind):
    ports = {}
    for item in pins:
        match = re.fullmatch(r'(\w+)(?:\[(\d+)\])?', item)
        require(match, f'Unsupported pin name {item}')
        ports.setdefault(match[1], set()).add(int(match[2]) if match[2] is not None else None)
    for name, bits in ports.items():
        if bits == {None}:
            yield name, f'  {kind} {name};'
        else:
            require(None not in bits and bits == set(range(max(bits) + 1)), f'Unexpected bus bits: {name}')
            yield name, f'  {kind} [{max(bits)}:0] {name};'


def testbench(parsed):
    inputs, outputs, statements, count, cycles, checks = parsed
    pins = list(declarations(inputs, 'reg')) + list(declarations(outputs, 'wire'))
    signals = '\n'.join(line for _, line in pins)
    hookups = ',\n'.join(f'    .{name}({name})' for name, _ in pins)
    drive = ', '.join(inputs)
    observed = ',\n    '.join(', '.join(outputs[i:i+6]) for i in range(0, len(outputs), 6))
    commands = '\n'.join(statements)
    return f'''`timescale 1ns/1ps
module {TB};
{signals}
  localparam integer WIDTH = {len(outputs)};
  localparam integer LENGTH = 584;
  integer compared = 0;
  integer cycles = 0;
  integer captures = 0;
  wire [WIDTH-1:0] observed = {{
    {observed}
  }};

  {TOP} dut (
{hookups}
  );

  task automatic check_bit(input logic expected, input logic actual,
                           input integer pattern, input integer bit_index,
                           input string group_name);
    if (expected !== 1'bx) begin
      compared = compared + 1;
      if (actual !== expected)
        $fatal(1, "ATPG_MISMATCH %s pattern=%0d bit=%0d cycle=%0d expected=%b actual=%b",
               group_name, pattern, bit_index, cycles, expected, actual);
    end
  endtask

  task automatic shift(input logic [LENGTH-1:0] in_bits,
                       input logic [LENGTH-1:0] out_bits, input integer pattern);
    // The pre-shift vector drives scan_en for one test cycle.
    clk_i = 1'b0;
    rst_ni = 1'b1;
    scan_en = 1'b1;
    #100;
    cycles = cycles + 1;
    for (integer i = LENGTH-1; i >= 0; i = i-1) begin
      scan_in = in_bits[i];
      #40;
      check_bit(out_bits[i], scan_out, pattern, LENGTH-1-i, "scan_out");
      #5 clk_i = 1'b1;
      #10 clk_i = 1'b0;
      #45;
      cycles = cycles + 1;
    end
  endtask

  task automatic capture(input logic [{len(inputs)-1}:0] pi, input logic clock_pulse,
                         input logic reset_pulse, input logic [WIDTH-1:0] po,
                         input integer pattern);
    {{{drive}}} = pi;
    #40;
    for (integer i = WIDTH-1; i >= 0; i = i-1)
      check_bit(po[i], observed[i], pattern, WIDTH-1-i, "_po");
    #5;
    if (clock_pulse) clk_i = 1'b1;
    if (reset_pulse) rst_ni = 1'b0;
    #10;
    if (clock_pulse) clk_i = 1'b0;
    if (reset_pulse) rst_ni = 1'b1;
    #45;
    cycles = cycles + 1;
    captures = captures + 1;
  endtask

  initial begin
    {{{drive}}} = '0;
    rst_ni = 1'b1;
    #200;
    cycles = 2;
{commands}
    if (cycles != {cycles} || compared != {checks} || captures != {count})
      $fatal(1, "ATPG_REPLAY_INCOMPLETE cycles=%0d compared=%0d patterns=%0d", cycles, compared, captures);
    $display("ATPG_SERIAL_PASS patterns=%0d cycles=%0d output_bit_checks=%0d", captures, cycles, compared);
    $finish;
  end
endmodule
'''


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('stil', type=Path)
    cli.add_argument('testbench', type=Path)
    args = cli.parse_args()
    parsed = parse(args.stil.read_text(encoding='ascii'))
    with args.testbench.open('x', encoding='ascii') as output:
        output.write(testbench(parsed))
    print(f'STIL_REPLAY_READY patterns={parsed[3]} cycles={parsed[4]} output_bit_checks={parsed[5]}')


if __name__ == '__main__':
    main()
