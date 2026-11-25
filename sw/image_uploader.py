#!/usr/bin/env python3
"""
image_uploader.py - send an image to the Atum A3 Nano image path.

Packet: 0xAA 0x55 sync, then 480*270 pixels in raster order, R,G,B bytes.
Total 2 + 388,800 bytes. Needs:  pip install pyserial pillow
Baud rate here must match CLKS_PER_BIT in the FPGA:
    115200 -> 434,  921600 -> 54,  3125000 -> 16 (50 MHz clock)
"""
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

import serial
import serial.tools.list_ports
from PIL import Image, ImageTk

W, H = 480, 270
SYNC = bytes([0xAA, 0x55])
BAUDS = ["115200", "921600", "3125000"]
CHUNK = 4096


def build_packet(path):
    """Resize to 480x270 RGB and return the full packet bytes."""
    img = Image.open(path).convert("RGB").resize((W, H), Image.LANCZOS)
    pkt = SYNC + img.tobytes()          # tobytes(): R,G,B per pixel, row-major
    assert len(pkt) == 2 + W * H * 3
    return pkt, img


def send_packet(port, baud, pkt):
    with serial.Serial(port, int(baud), timeout=1, write_timeout=10) as s:
        for i in range(0, len(pkt), CHUNK):
            s.write(pkt[i:i + CHUNK])
        s.flush()


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("A3 Nano Image Uploader")
        self.resizable(False, False)
        self.path = None
        self.pkt = None
        self.preview_img = None

        top = ttk.Frame(self, padding=10)
        top.grid(row=0, column=0, sticky="nsew")

        ttk.Button(top, text="Choose image", command=self.choose).grid(row=0, column=0, sticky="w")
        self.file_lbl = ttk.Label(top, text="No file selected")
        self.file_lbl.grid(row=0, column=1, sticky="w", padx=8)

        ttk.Label(top, text="COM port").grid(row=1, column=0, sticky="w", pady=(8, 0))
        self.port_var = tk.StringVar()
        self.port_cb = ttk.Combobox(top, textvariable=self.port_var, width=12, state="readonly")
        self.port_cb.grid(row=1, column=1, sticky="w", pady=(8, 0))
        ttk.Button(top, text="Refresh", command=self.refresh_ports).grid(row=1, column=2, padx=6, pady=(8, 0))

        ttk.Label(top, text="Baud").grid(row=2, column=0, sticky="w", pady=(8, 0))
        self.baud_var = tk.StringVar(value=BAUDS[0])
        ttk.Combobox(top, textvariable=self.baud_var, values=BAUDS, width=12,
                     state="readonly").grid(row=2, column=1, sticky="w", pady=(8, 0))

        self.send_btn = ttk.Button(top, text="Send", command=self.send, state="disabled")
        self.send_btn.grid(row=3, column=0, columnspan=3, sticky="ew", pady=10)

        self.status = ttk.Label(top, text="Ready")
        self.status.grid(row=4, column=0, columnspan=3, sticky="w")

        self.preview = ttk.Label(top, text="(preview)", relief="sunken", width=60)
        self.preview.grid(row=0, column=3, rowspan=5, padx=(12, 0))

        self.refresh_ports()

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_cb["values"] = ports
        if ports and self.port_var.get() not in ports:
            self.port_var.set(ports[0])

    def choose(self):
        path = filedialog.askopenfilename(
            filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp *.gif"), ("All files", "*.*")])
        if not path:
            return
        try:
            self.pkt, img = build_packet(path)
        except Exception as e:
            messagebox.showerror("Image error", str(e))
            return
        self.path = path
        self.file_lbl.config(text=path.split("/")[-1].split("\\")[-1])
        thumb = img.copy()
        thumb.thumbnail((480, 270))
        self.preview_img = ImageTk.PhotoImage(thumb)
        self.preview.config(image=self.preview_img, text="")
        self.send_btn.config(state="normal")
        self.status.config(text=f"Ready: {W}x{H} RGB, {len(self.pkt)} bytes")

    def send(self):
        port = self.port_var.get()
        if not port:
            messagebox.showwarning("No port", "Pick a COM port first.")
            return
        self.send_btn.config(state="disabled")
        self.status.config(text="Sending...")
        threading.Thread(target=self._worker, args=(port, self.baud_var.get()), daemon=True).start()

    def _worker(self, port, baud):
        try:
            send_packet(port, baud, self.pkt)
            self.after(0, lambda: self.status.config(text=f"Sent {len(self.pkt)} bytes at {baud}"))
        except Exception as e:
            self.after(0, lambda: messagebox.showerror("Send failed", str(e)))
            self.after(0, lambda: self.status.config(text="Send failed"))
        finally:
            self.after(0, lambda: self.send_btn.config(state="normal"))


if __name__ == "__main__":
    App().mainloop()
