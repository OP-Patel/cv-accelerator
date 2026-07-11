# Milestone 1 RTL logic walkthrough

This document explains the bring-up logic from the electrical inputs through the status text. It is intentionally detailed so each clocked behavior can be followed in simulation.

## 1. Clock and time conversion

The board clock is 100 MHz, so one clock period is 10 ns. Any human-scale delay must therefore be represented as a count of many clock edges.

The heartbeat uses counter bit 26. A binary counter bit toggles after `2^bit_number` increments, so bit 26 changes after `2^26 = 67,108,864` clocks. At 100 MHz that is 0.67108864 seconds per LED state and 1.34217728 seconds for one complete off/on cycle.

The default debounce interval is 1,000,000 clocks. At 100 MHz this equals 10 ms. A mechanical contact must remain consistently different from its current accepted state for the whole interval before the cleaned output changes.

The periodic message interval is 500,000,000 clocks, exactly 5 seconds at 100 MHz.

## 2. Reset synchronizer

`reset_btn` comes from a mechanical button and is not aligned to `clk_100mhz`. `reset_sync.sv` uses two flip-flops with an asynchronous set:

1. Pressing the button sets both flip-flops immediately, without waiting for a clock. This is asynchronous assertion and rapidly puts all downstream state into reset.
2. Releasing the button does not asynchronously clear the state. On the first following clock, the first flip-flop becomes zero while the second still sees the first flip-flop's old value of one.
3. On the second following clock, the second flip-flop sees zero. Only then does `sync_reset_out` become zero.

That sequence is called asynchronous assertion and synchronous deassertion. It prevents different registers from leaving reset at arbitrary points inside a clock period. The second stage also gives the first stage a full clock period to resolve possible metastability caused by release near a clock edge.

## 3. Input synchronizer and debounce filter

Every extra push button and slide switch passes through its own `debounce` instance.

The two-bit `synchronizer` shift register is the clock-domain crossing boundary. On each rising edge, stage zero samples the physical pin and stage one samples the previous stage-zero value. Only stage one is consumed by the debounce filter. The `ASYNC_REG` property tells Vivado that these registers are a synchronizer pair so placement and timing analysis can treat them appropriately.

The filter compares synchronized input with `clean_out`:

- If they match, there is no proposed state change, so `stable_counter` is cleared.
- If they differ, the counter increments once per clock.
- If the input bounces back to the accepted value before the threshold, the counter is cleared and the attempted transition is rejected.
- If the input remains different for `STABLE_CYCLES` consecutive samples, `clean_out` takes the new value and the counter clears.

The parameter has a special `STABLE_CYCLES <= 1` generate branch. That branch retains the two-stage synchronizer but removes the long filter delay. It exists mainly to keep simulations fast while exercising the same top-level structure.

## 4. UART bit timing and framing

The transmitter implements 115200 8N1:

- 115200 symbols per second;
- 8 data bits;
- no parity bit;
- 1 stop bit.

The ideal clocks per UART bit are `100,000,000 / 115,200 = 868.0555...`. Hardware needs an integer count, so the expression adds half the baud rate before integer division and produces 868. The actual baud is approximately 115207.37, an error of about +0.0064%, far inside normal UART tolerance.

An idle UART line is logic one. When `send` is high while `busy` is low, the transmitter constructs this ten-bit frame:

```text
frame[0]   = 0       start bit
frame[1]   = data[0] least-significant data bit
...
frame[8]   = data[7] most-significant data bit
frame[9]   = 1       stop bit
```

The concatenation `{1'b1, data, 1'b0}` creates exactly that ordering because the rightmost concatenation bit becomes `frame[0]`.

On acceptance, `tx` immediately becomes zero and `busy` becomes one. `baud_counter` then counts 868 clock periods for each frame bit. At each terminal count it clears and advances `bit_index`. After the stop bit has remained high for its complete bit interval, `busy` falls and `tx` remains at the idle-high level.

A `send` request while `busy` is one is ignored. This keeps the active frame immutable; the top-level message controller waits for completion before requesting the next character.

## 5. Status-message character lookup

`status_character` is combinational lookup logic. It maps a character index to ASCII for:

```text
M1 OK SW=0xN\r\n
```

`N` is the hexadecimal value of the four debounced switches. Values 0 through 9 add the switch value to ASCII `0`; values 10 through 15 add the offset to ASCII `A`. Carriage return (`0x0D`) and line feed (`0x0A`) make normal serial terminals display one status record per line.

At the start of each line, `sw_clean` is copied into `message_sw`. This snapshot matters: if a user flips a switch while the line is being transmitted, the hexadecimal character still belongs to one coherent sample rather than changing midway through generation.

## 6. Message scheduling and handshake state machine

`message_pending` is a one-entry request latch. After reset, a short input-settle counter waits for the two synchronizer clocks plus the configured debounce interval before it requests the first line. This prevents an initial line from incorrectly reporting zero when a switch was already on during reset. The five-second timer and a rising edge from any debounced extra button also set the latch. Multiple requests that arrive while a line is active are intentionally coalesced into one later line; this prevents an unbounded message queue.

Button edges are found with `btn_clean & ~btn_clean_delayed`. `btn_clean_delayed` holds the previous cycle. A bit is therefore one only on the first cycle where a cleaned button changes from released to pressed. Holding a button cannot repeatedly flood the UART.

The message state machine has four states:

1. `MSG_IDLE`: wait for `message_pending`; snapshot switches, select character zero, and clear the consumed request.
2. `MSG_SEND_PULSE`: drive `uart_send` high for exactly one clock.
3. `MSG_WAIT_BUSY`: wait until the UART has observed that pulse and raised `uart_busy`.
4. `MSG_WAIT_DONE`: wait until the entire ten-bit character, including its stop bit, is finished. Then load the next character or return to idle after line feed.

The separate wait-for-busy state is necessary because all registers use nonblocking assignments. On the edge where the controller raises `uart_send`, the UART still sees its previous value. On the next edge the UART accepts the request and schedules `busy` high, while the controller still sees the previous low `busy`. Waiting explicitly for high and then low avoids advancing the message index early or losing every other character.

## 7. LED behavior

While synchronized reset is high, all LEDs are forced off. Otherwise:

- `led[0]` shows counter bit 26 and is the heartbeat;
- `led[1]` shows debounced `sw[0]`;
- `led[2]` shows debounced `sw[1]`;
- `led[3]` shows debounced `sw[2]`.

`sw[3]` is not omitted from validation: it appears in the UART hexadecimal nibble along with the other three switches. There are only three LEDs left after allocating one to the heartbeat.

## 8. USB-UART receive input

The FTDI-to-FPGA receive path is constrained and passed through a two-stage synchronizer, but no receiver state machine consumes it in Milestone 1. This makes the physical interface explicit without pretending that bidirectional UART functionality has been implemented. The milestone requires readable FPGA-to-laptop status output, so transmit is the functional direction.

## 9. Verification logic

`tb_uart_tx.sv` uses a deliberately small exact ratio of 10 clocks per UART bit. It verifies idle-high behavior during and after reset, start-bit assertion, all eight bits of `0xA5` in least-significant-bit-first order, the stop bit, `busy` throughout the frame, and return to idle after the complete stop interval. It also pulses `send` during a frame and confirms the original byte remains intact.

`tb_arty_m1_bringup_top.sv` overrides the human-scale parameters with short simulation values. It verifies asynchronous reset behavior, two-clock reset release, heartbeat movement, switch-to-LED debouncing, initial UART activity, the first transmitted ASCII `M`, and restoration of LEDs/UART idle when reset is asserted again.

Parameter overrides change only waiting time in simulation. The synthesized defaults remain 100 MHz, 115200 baud, 10 ms debounce, 5-second reporting, and counter bit 26.
