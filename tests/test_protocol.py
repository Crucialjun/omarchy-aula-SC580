import importlib.util, json, os, sys, struct
HERE = os.path.dirname(os.path.abspath(__file__))
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("sc580ctl", SourceFileLoader("sc580ctl", os.path.join(HERE, "..", "bin", "sc580ctl")))
sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)

class FakeDevice:
    """Behaves like the mouse: echoes cmd, status 0, answers 0x30/0x13."""
    def __init__(self):
        self.path = "(fake)"; self.sent = []; self.queue = []; self.busy_once = False
    def close(self): pass
    def write(self, payload):
        assert len(payload) == 32
        assert payload[31] == sum(payload[4:31]) & 0xFF, "bad checksum"
        self.sent.append(bytes(payload))
        rep = bytearray(32); rep[0] = payload[0]
        if self.busy_once:
            rep[1] = 1; self.busy_once = False; self.queue.append(bytes(rep)); return
        if payload[0] == 0x30:
            rep[4:15] = bytes([0x4d,0x31,0x33,0x37,0x01,0x16,0x11,0xaa,0x02,0x64,0x01])  # real SC580 reply
        elif payload[0] == 0x13:
            rep[4] = 0x20  # stage index 2
        # sprinkle an async notification before the reply
        n = bytearray(32); n[0] = 0xD2; n[1] = 0x30
        self.queue.append(bytes(n)); self.queue.append(bytes(rep))
    def read(self, timeout):
        return self.queue.pop(0) if self.queue else None

def mouse():
    f = FakeDevice(); return sc.Mouse(f, "fake"), f

def test_packet_framing():
    p = sc.build_packet(0x02, bytes([0x01]))
    assert p[:5] == bytes([0x02, 0x00, 0x01, 0x01, 0x01]) and p[31] == 0x01
    p = sc.build_packet(0x09, bytes(range(27)), n_packages=2, package_index=1)
    assert p[2] == 0x12 and p[3] == 27 and p[31] == sum(range(27)) & 0xFF

def test_info_and_dpi():
    m, f = mouse()
    i = m.get_info(); assert i["identity"] == "M137" and i["battery"] == 100 and i["full"] and not i["charging"] and i["online"] and i["sensor"] == "PAW3311" and i["firmware"] == "1.6.01"
    assert m.get_dpi_stage() == 2

def test_set_dpi_layout():
    m, f = mouse()
    m.set_dpi([800, 1600, 2400, 3200, 6400, 12000], 1)
    d = f.sent[-1]
    assert d[0] == 0x03 and d[3] == 27
    assert d[4] == 0 and d[5] == (1 << 4) | 6
    codes = [struct.unpack_from("<H", d, 6 + 4 * i)[0] for i in range(6)]
    assert codes == [7, 15, 23, 31, 63, 119]
    assert all(struct.unpack_from("<H", d, 8 + 4 * i)[0] == 0 for i in range(6))

def test_rate_key_wireless_sensor():
    m, f = mouse()
    m.set_rate(1000); assert f.sent[-1][4] == 0x01 and f.sent[-1][3] == 1
    m.set_rate(125);  assert f.sent[-1][4] == 0x08
    m.set_key(6, sc.parse_key_function("dpi_up")); assert f.sent[-1][:8] == bytes([1, 0, 1, 4, 5, 0x50, 0x02, 0x00])
    m.set_key(1, sc.parse_key_function("kbd:ctrl+shift+t")); assert f.sent[-1][4:8] == bytes([0, 0x80, 0x03, 0x17])
    m.set_wireless(180, True, False, 8); assert f.sent[-1][4:8] == bytes([6, 1, 0, 8]) and f.sent[-1][3] == 4
    m.set_sensor(1, True, False); assert f.sent[-1][4:9] == bytes([1, 1, 0, 0, 0]) and f.sent[-1][3] == 5
    m.factory_reset(); assert f.sent[-1][4] == 0xFF and f.sent[-1][0] == 0x0F

def test_busy_retry_and_offline():
    m, f = mouse(); f.busy_once = True
    m.set_rate(500); assert len(f.sent) == 2
    class Off(FakeDevice):
        def write(self, payload):
            rep = bytearray(32); rep[0] = payload[0]; rep[1] = 2; self.queue.append(bytes(rep))
    m2 = sc.Mouse(Off(), "fake")
    try: m2.set_rate(500); assert False
    except sc.DeviceOffline: pass

def test_notifications():
    assert sc.parse_notification(bytes([0xD2, 0x20]) + bytes(30)) == {"event": "dpi", "stage": 3}
    assert sc.parse_notification(bytes([0xD1, 1, 55, 1]) + bytes(28)) == {"event": "power", "online": True, "battery": 55, "charge_state": 1, "charging": True, "full": False}

def test_rdesc_scan():
    assert sc._rdesc_has_usage_page(bytes([0x06, 0x02, 0xFF, 0x09, 0x01]), 0xFF02)
    assert not sc._rdesc_has_usage_page(bytes([0x05, 0x01, 0x09, 0x02]), 0xFF02)

def test_dpi_validation():
    for bad in (150, 850, 12100, 0):
        try: sc.dpi_to_code(bad); assert False
        except ValueError: pass

def test_apply_sequence():
    m, f = mouse(); m.apply_config(sc.default_config())
    cmds = [p[0] for p in f.sent]
    assert cmds == [1]*6 + [3, 2, 6, 7]

if __name__ == "__main__":
    fails = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            try: fn(); print("ok  ", name)
            except Exception as e: fails += 1; print("FAIL", name, repr(e))
    sys.exit(1 if fails else 0)
