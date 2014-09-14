import sys, time
import numpy
import serial
import sdl2
import sdl2.ext

baudrate = 1e6

maxdb = 40
mindb = maxdb - 20
N = 1024

def rgb2int(r, g, b) :
	return b + (g<<8) + (r<<16)
def byte2color(b) :
	return b + (b<<8) + (b<<16)
def limit(a) :
	global mindb
	global maxdb
	data = 20*numpy.log10(a)
	data[a == 0] = mindb
#	if data.min() < mindb :
#		mindb = data.min()
#		print "Minimum:",mindb
	data[a == 0] = mindb
#	if data.max() > maxdb :
#		maxdb = data.max()
#		print "Maximum:",maxdb
	data[data > maxdb] = maxdb
	data[data < mindb] = mindb
	data = (data - mindb) * 1.0 / (maxdb - mindb)
	pix = numpy.array(data * ((1<<8) - 1), dtype='int32')
	return pix + (pix * (1<<8)) + (pix * (1<<16))

def run(port) :
	w,h = (1300,N/2+1)
	sdl2.ext.init()
	window = sdl2.ext.Window("Waterfall", size=(w,h))
	surface = window.get_surface()
	pix = sdl2.ext.pixels2d(surface)
	window.show()
	running = True
	col = 0
	a = 0
	hwnd = numpy.hamming(N)
	bins = numpy.zeros((256,),dtype='int32')
	bar = numpy.zeros((h,), dtype=pix.dtype)
	pix[w-257,:] = numpy.ones((h,), dtype=pix.dtype) * rgb2int(255, 0, 0)
	with serial.Serial(port, baudrate, timeout=1) as fpga :
		while running :
			events = sdl2.ext.get_events()
			for event in events :
				if event.type == sdl2.SDL_QUIT :
					running = False
					break
			raw = fpga.read(N)
			data = numpy.array( [ord(c) for c in raw] )
			# Plot a histogram
			bins[:] = 0
			for sample in data :
				bins[sample] += 1
			bins *= 513
			bins /= N
			for b in range(0, 256) :
				bar[:] = 0
				bar[h - bins[b]:] = byte2color(255)
				pix[w-256+b,:] = bar
			# Remove DC
			data = data - data.mean()
			# Plot a waterfall FFT
			if len(data) < N :
				running = False
			else :
				data = numpy.abs(numpy.fft.rfft(hwnd * data)).reshape((1,h))
				pix[col,:] = limit(data)
				col = (col + 1) % (w - 257)
			window.refresh()
		window.hide()
		sdl2.ext.quit()
		print "Closing serial port..."
		fpga.close()
		return 0

if __name__ == "__main__" :
	sys.exit(run(sys.argv[1]))
