from serial import Serial
from matplotlib import pyplot as plt
import numpy as np
from time import sleep, time
from argparse import ArgumentParser
start_time = 0
class Command:
    @staticmethod
    def rate(value: float):
        return f"rate {value:.4f}" 

    @staticmethod
    def duty(value):
        return f"duty {value:.4f}"

    @staticmethod
    def encoder():
        return "encoder"
    
    @staticmethod
    def temp_motor():
        return "temp_motor"

    @staticmethod
    def temp_mosfet():
        return "temp_mosfet"

    @staticmethod
    def temp():
        return "temp"

    @staticmethod
    def reset_encoder():
        return "reset_encoder" 


BROADCAST = -1
class MotorNetwork:
    _serial: Serial
    _motors = dict[int, str]
    
    def __init__(self, serial_port: str) -> None:
        self._serial = Serial(port=serial_port, baudrate=115200)
        self._motors = {BROADCAST: "*"}
    
    def add_motor(self, id: int):
        self._motors[id] = str(id)
    
    def build_cmd(self, id: int, cmd) -> str:
        motor_id = self._motors.get(id)
        cmd = F"{motor_id} {cmd}\n"
        return cmd

    def send(self, id: int, cmd: str) -> str | None:
        cmd = self.build_cmd(id, cmd)
        self._serial.write(cmd.encode())
        if debug:
            print(f"{(time() - start_time):.1f} >{cmd.encode('utf-8')}")
        if id == BROADCAST:
            sleep(0.010)
            return None
        response = self._serial.read_until(expected=b'\n')
        if debug:
            print(f"{(time() - start_time):.1f} <{response}")
        sleep(0.010)
        return response.decode().rstrip('\n').split()[1]

    def close(self):
        self._serial.close()

parser = ArgumentParser(__file__)
parser.add_argument('port')
parser.add_argument('--duty', action='store_true')
parser.add_argument('--encoder', action='store_true')
parser.add_argument('--temperature', action='store_true')
parser.add_argument('--all', action='store_true')
parser.add_argument('--show', action='store_true')
parser.add_argument('--plot', action='store_true')
parser.add_argument('--forever', action='store_true')
parser.add_argument('--count', action='store', type=int)


args = parser.parse_args()
debug = args.show
if args.all:
    args.duty = True
    args.encoder = True
    args.temperature = True


network = MotorNetwork(args.port)
motors = [0, 1]
[network.add_motor(i) for i in motors]

network.send(BROADCAST, Command.rate(0.005)) # default
start_time = time()
while args.forever or args.count > 0:
    if args.duty:
        print("--- RAMP UP ---")
        for duty in np.linspace(0.0, 1.0, 41):
            [network.send(i, Command.duty(duty)) for i in motors]
            sleep(0.100)
        sleep(1)
        
        print("--- RAMP DOWN ---")
        for duty in np.linspace(1.0, -1.0, 2*41):
            [network.send(i, Command.duty(duty)) for i in motors]
            sleep(0.100)
        sleep(1)

        print("--- BROADCAST STOP ---")
        for duty in np.linspace(-1.0, 0.0, 41):
            network.send(BROADCAST, Command.duty(duty))
            sleep(0.100)
        sleep(1)

    if args.encoder:
        angle = []

        print("--- RESET ENCODER ---")
        network.send(BROADCAST, Command.duty(0.0))
        m0 = network.send(0, Command.reset_encoder())
        m1 = network.send(1, Command.reset_encoder())
        angle.append([float(m0), float(m1)])
        print(m0, m1)

        print("--- ENCODER ---")
        network.send(BROADCAST, Command.duty(0.3))
        for i in range(0, 100):
            m0 = network.send(0, Command.encoder())
            m1 = network.send(1, Command.encoder())
            angle.append([float(m0), float(m1)])

        network.send(BROADCAST, Command.duty(0.0))
            


    if args.temperature:
        print("--- TEMPERATURE ---")
        tm = network.send(0, Command.temp_motor())
        tf = network.send(0, Command.temp_mosfet())
        t = network.send(0, Command.temp())
        print(t, tm, tf)

        tm = network.send(1, Command.temp_motor())
        tf = network.send(1, Command.temp_mosfet())
        t = network.send(1, Command.temp())
        print(t, tm, tf)


    if args.encoder and args.plot:
        plt.figure()
        plt.plot(angle)
        plt.legend(['motor 0', 'motor 1'])
        plt.show()
    args.count -= 1