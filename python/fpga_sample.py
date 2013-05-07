#!/usr/bin/python
# -*- coding: utf-8 -*-
# Capture 3 seconds of stereo audio from alsa_pcm:capture_1/2; then play it back.
#
# Copyright 2003, Andrew W. Schmeder
# This source code is released under the terms of the GNU Public License.
# See LICENSE for the full text of these terms.

import numpy as np
import Gnuplot
import jack
import time
import sys
import serial

Nsamples = 2**16
baudrate = 1e6

print "Gathering samples, %4.4f seconds"%(10.*Nsamples/baudrate,)

fpga = serial.Serial('/dev/ttyUSB0',baudrate,timeout=1)
samples = [ord(c) if ord(c) < 128 else ord(c) - 256 for c in fpga.read(Nsamples)]
fpga.close()

Gnuplot.GnuplotOpts.default_term = 'postscript eps enhanced color size 40cm,25cm blacktext'

colormap = 'WhiteBlueGreenYellowRed.pal'
colormap = 'WhiteBlue.pal'
colormap = 'BkBlAqGrYeOrReViWh200.pal'

mean = np.array(samples) / 128.

N = Nsamples
fs = baudrate/10
scale = 20.
Nwin = 2**10

print "Window length: %4.4f sec"%(Nwin/fs,)

T = N / fs
Nstep = N / Nwin
df = Nstep / T

s = np.empty((Nstep*32,Nwin))
for idx in range(0, s.shape[0]) :
	i = idx * N / s.shape[0]
	if i+Nwin > N :
		break
	s[idx,:] = mean[i:i+Nwin]
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

Smax = np.log10(S.max()).round(1)
#Smax = np.log10(3e-5)
Smin = 10**((Smax - scale/10.).round(1))
Smax = 10**Smax

plot = Gnuplot.Gnuplot(debug=0)
file = 'test.eps'
plot.set_string('output', file)
plot.xlabel(s='Time [sec]')
plot.ylabel(s='Frequency [kHz]')
#plot.set_string('cblabel', cblabel)
y /= 1000.
plot.set_range('xrange', (x.min(), x.max()))
#plot('set xtics %f'%
plot.set_range('yrange', (y[1], y[-1]))
plot('set ytics %f'%1)
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
