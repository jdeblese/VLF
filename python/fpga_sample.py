#!/usr/bin/python
# -*- coding: utf-8 -*-
# Capture 3 seconds of stereo audio from alsa_pcm:capture_1/2; then play it back.
#
# Copyright 2003, Andrew W. Schmeder
# This source code is released under the terms of the GNU Public License.
# See LICENSE for the full text of these terms.

import numpy as np
import Gnuplot
import time
import sys
import serial

assert len(sys.argv) > 1

# ADC Settings
Nsamples = 2**16
baudrate = 1e6
 # Plot Settings
Gnuplot.GnuplotOpts.default_term = 'png enhanced size 1300,600'
file = 'test.png'
colormap = 'WhiteBlueGreenYellowRed.pal'
colormap = 'WhiteBlue.pal'
colormap = 'BkBlAqGrYeOrReViWh200.pal'

# Derived values
N     = Nsamples
fs    = baudrate/10  # Sample Rate (10 bits/sample)
scale = 12.
Nwin  = 2**10        # Window width
T     = N / fs       # Sample Period
Nstep = N / Nwin     # Number of windows in given sample set
df    = Nstep / T    # Frequency Resolution

# *** Gather Data ***

print "Gathering samples, %4.4f seconds"%(10.*Nsamples/baudrate,)

fpga = serial.Serial(sys.argv[1],baudrate,timeout=1)
samples = []
while len(samples) < N :
	samples += [ord(c) for c in fpga.read(N - len(samples))]
	print "Sample count: %d/%d"%(len(samples),N)
fpga.close()

data = np.array(samples, dtype='uint16')
# Convert to unsigned, temporarily
data = np.array(data + 128, dtype='uint8')
print "Data range [%d,%d], mean %d"%(data.min(),data.max(),data.mean())

plot = Gnuplot.Gnuplot(debug=0)
plot.set_string('output', 'oscilloscope.png')
plot.xlabel(s='Time [sec]')
plot.ylabel(s='Amplitude')
t = np.arange(0, T, 1./fs)
pldata = (Gnuplot.Data(t[:512], data[:512], with_="points", title=None),)
plot.plot(*pldata)

bins = np.arange(-128, 128, dtype='int32')
bindata = np.zeros(bins.shape, dtype='int32')
for sample in data :
	bindata[sample] += 1
plot = Gnuplot.Gnuplot(debug=0)
plot.set_string('output', 'histogram.png')
plot.set_range('xrange', (bins.min(),bins.max()))
plot('set xtics 16')
plot('set logscale y')
plot('set style fill solid border -1')
plot('set boxwidth 1.0 relative')
pldata = (Gnuplot.Data(bins, bindata, with_="boxes", title=None),)
plot.plot(*pldata)


data  = data / 128.  # Normalize to [0, 2]
data -= 1            # Convert to signed [-1, 1]
data *= 3.3 / 2      # Voltage

# *** Calculate Spectrum ***

print "Window length: %4.4f sec"%(Nwin/fs,)

s = np.empty((Nstep*32,Nwin))
for idx in range(0, s.shape[0]) :
	i = idx * N / s.shape[0]
	if i+Nwin > N :
		break
	s[idx,:] = data[i:i+Nwin]
s = s[:idx,:]

if (s == 0).all() :
	print "Null signal captured"
	sys.exit(-1)

dx = T / s.shape[0]
x = np.arange(0, T - dx/2., dx)

win = np.hamming(Nwin)
#win = np.blackman(Nwin)
S = np.empty((s.shape[0], s.shape[1]/2+1), dtype='complex128')
for idx in range(0, s.shape[0]) :
	S[idx,:] = np.fft.rfft(win*s[idx,:]) * 2 / s.shape[1]
S = np.abs(S)
y = np.arange(0, (fs+df)/2, df)

Smax = np.log10(S.max())
#Smax = np.log10(3e-5)
Smin = 10**((Smax - scale/10.).round(1))
Smax = 10**Smax

plot = Gnuplot.Gnuplot(debug=0)
plot.set_string('output', file)
plot.xlabel(s='Time [sec]')
plot.ylabel(s='Frequency [kHz]')
#plot.set_string('cblabel', cblabel)
y /= 1000.  # Units: kHz
plot.set_range('xrange', (x.min(), x.max()))
#plot('set xtics %f'%
plot.set_range('yrange', (y[1], y[-1]))
plot('set ytics %f'%5)
plot.set_range('cbrange', (Smin,Smax))
#plot('set logscale ycb')
plot('set logscale cb')
#plot('set format '+logscale+' "10^{%L} "')
#plot('set size ratio 1')
plot('set pm3d flush begin corners2color c1 map')
#plot('set palette negative model RGB file "' + colormap + '"')
plot('set palette model RGB file "' + colormap + '"')
assert S.shape[0] == x.shape[0]
assert S.shape[1] == y.shape[0]
dx = x[1] - x[0]
x = np.concatenate( (x,[x[-1]+dx]) )
dy = y[1] - y[0]
y = np.concatenate( (y,[y[-1]+dy]) )
S = np.concatenate( (S,np.zeros((S.shape[0],1))), 1)
S = np.concatenate( (S,np.zeros((1,S.shape[1]))), 0)
pldata = (Gnuplot.GridData(S[:,1:], x, y[1:], filename='raw.dat', title=None),)
plot.splot(*pldata)
