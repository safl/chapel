/***************************************************************************
 *cr
 *cr            (C) Copyright 2007 The Board of Trustees of the
 *cr                        University of Illinois
 *cr                         All Rights Reserved
 *cr
 ***************************************************************************/

/* 
 * C code for creating the Q data structure for fast convolution-based 
 * Hessian multiplication for arbitrary k-space trajectories.
 *
 * Inputs:
 * kx - VECTOR of kx values, same length as ky and kz
 * ky - VECTOR of ky values, same length as kx and kz
 * kz - VECTOR of kz values, same length as kx and ky
 * x  - VECTOR of x values, same length as y and z
 * y  - VECTOR of y values, same length as x and z
 * z  - VECTOR of z values, same length as x and y
 * phi - VECTOR of the Fourier transform of the spatial basis 
 *      function, evaluated at [kx, ky, kz].  Same length as kx, ky, and kz.
 *
*/

//use GPUDist, GPUExplicitConstDist, Time;
use GPUDist, GPUConstDist, Time;

config var timing : bool = true;
var timer: Timer;

//config const filename = "32_32_32_dataset.bin";
config const filename = "64_64_64_dataset.bin";
//config const outfilename  = "32_32_32_dataset.out";
config const outfilename  = "64_64_64_dataset.out";
param KERNEL_PHI_MAG_THREADS_PER_BLOCK = 512;
param KERNEL_Q_THREADS_PER_BLOCK = 256;
param KERNEL_Q_K_ELEMS_PER_GRID = 1024;
param PIx2 = 6.2831853071795864769252867665590058;

_extern def fopen(name: string, mode: string): _file;
_extern def fread(inout data, size: int, n: int, f: _file): int;
_extern def fwrite(inout data, size: int, n: int, f: _file): int;
_extern def fclose(f: _file);

record kValues {
  var Kx : real(32);
  var Ky : real(32);
  var Kz : real(32);
  var PhiMag : real(32);
}

def inputData(infile, _numK, _numX, inout kx, out ky, out kz, out x, out y, out z, out phiR, out phiI, out dR, out dI)
{
  var ret : int(32);
  var size = numBytes(real(32));
  ret = fread(kx(0), size, _numK, infile);
  writeln(ret);
  ret = fread(ky(0), size, _numK, infile);
  writeln(ret);
  ret = fread(kz(0), size, _numK, infile);
  writeln(ret);
  ret = fread(x(0), size, _numX, infile);
  writeln(ret);
  ret = fread(y(0), size, _numX, infile);
  writeln(ret);
  ret = fread(z(0), size, _numX, infile);
  writeln(ret);
  ret = fread(phiR(0), size, _numK, infile);
  writeln(ret);
  ret = fread(phiI(0), size, _numK, infile);
  writeln(ret);
  ret = fread(dR(0), size, _numK, infile);
  writeln(ret);
  ret = fread(dI(0), size, _numK, infile);
  writeln(ret);
}

def outputData(outfile, in numX, in Qr, in Qi)
{
  var size = numBytes(int(32));
  var ret : int;
  writeln("outputing ", size, " per element, and ", numX, " elements = ", size * numX);
  ret = fwrite(numX, size, 1, outfile);
  writeln("wrote ", ret, " bytes");
  ret = fwrite(Qr(0), size, numX, outfile);
  writeln("wrote ", ret, " bytes");
  ret = fwrite(Qi(0), size, numX, outfile);
  writeln("wrote ", ret, " bytes");
}

def main() {
  var numX, numK : int;
  var original_numK, original_numX : int;
  var infile, outfile: _file;
  var ret : int;
  infile = fopen(filename, "rb");
  ret = fread(numK, numBytes(int), 1, infile);
  writeln(ret);
  ret = fread(numX, numBytes(int), 1, infile);
  writeln(ret);
  writeln("numK = ", numK, " numX = ", numX);

  original_numK = numK;
  original_numX = numX;
  writeln(numX, " pixels in output; ", original_numK, " samples in trajectory; using ", numK,"  samples");

  const numX_range = 0..original_numX-1;


  const numK_range = 0..original_numK-1;
  const GPUBlockDist_PhiMag = new dmap(new GPUDist(rank=1, tbSizeX=KERNEL_PHI_MAG_THREADS_PER_BLOCK));
  const GPUBlockDist_Qkern = new dmap(new GPUDist(rank=1, tbSizeX=KERNEL_Q_THREADS_PER_BLOCK));
  const GPUConstantMemDist = new dmap(new GPUConstDist(rank=1));
  const gpu_space : domain(1, int) dmapped GPUBlockDist_PhiMag = numK_range;
  var constmemspace : domain(1, int) dmapped GPUConstantMemDist = 0..KERNEL_Q_K_ELEMS_PER_GRID-1;

  const gpu_numX_space : domain(1, int) dmapped GPUBlockDist_Qkern = numX_range;

  var dR : [gpu_space] real(32);
  var dI : [gpu_space] real(32);
  var phiR : [gpu_space] real(32);
  var phiI : [gpu_space] real(32);
  var phiMag : [gpu_space] real(32);
  var kx : [gpu_space] real(32);
  var ky : [gpu_space] real(32);
  var kz : [gpu_space] real(32);
  var x : [gpu_numX_space] real(32);
  var y : [gpu_numX_space] real(32);
  var z : [gpu_numX_space] real(32);
  var Qr : [gpu_numX_space] real(32);
  var Qi : [gpu_numX_space] real(32);

  inputData(infile, numK, numX, kx, ky, kz, x, y, z, phiR, phiI, dR, dI);
  fclose(infile);

  /* GPU section 1 (precompute PhiMag) */
  var totaltime = 0.0;
if timing then timer.start();
  forall indexK in gpu_space do {
    const (real_val, imag_val) = (phiR(indexK), phiI(indexK));
    phiMag(indexK) = real_val * real_val + imag_val * imag_val;
  }
if timing then timer.stop();
if timing then totaltime += timer.elapsed();

  var kVals : [numK_range] kValues;

  var constMem : [constmemspace] kValues;


  for k in numK_range {
    kVals(k).Kx = kx(k);
    kVals(k).Ky = ky(k);
    kVals(k).Kz = kz(k);
    kVals(k).PhiMag = phiMag(k);
  }

  writeln("Second kernel");
  forall i in gpu_numX_space do {
    Qr(i) = 0.0 : real(32);
    Qi(i) = 0.0 : real(32);
  }

  var QGrids = (numK + KERNEL_Q_K_ELEMS_PER_GRID - 1)/ KERNEL_Q_K_ELEMS_PER_GRID;
  for QGrid in 0..QGrids-1 do {

    var kGlobalIndex = QGrid * KERNEL_Q_K_ELEMS_PER_GRID;
    var numElems = min(KERNEL_Q_K_ELEMS_PER_GRID, numK - kGlobalIndex);
    writeln("numElemns = ", KERNEL_Q_K_ELEMS_PER_GRID, " or ", numK - kGlobalIndex, " for qgrids = ", QGrids-1);
    constMem = kVals(kGlobalIndex..(kGlobalIndex+numElems-1));

    writeln("Third kernel");
if timing then timer.start();
    forall xIndex in gpu_numX_space do {
      const (sX, sY, sZ) = (x(xIndex), y(xIndex), z(xIndex));
      var (sQr, sQi) = (Qr(xIndex), Qi(xIndex));
      
      var kIndex = 0;
      var iIndex = kGlobalIndex;
      if numK % 2 then {
        var expArg = PIx2 : real(32) * (constMem(kIndex).Kx * sX + constMem(kIndex).Ky * sY + constMem(kIndex).Kz * sZ);
        const phiMag_scalar = constMem(kIndex).PhiMag;
        sQr += phiMag_scalar * cos(expArg);
        sQi += phiMag_scalar * sin(expArg);
        kIndex += 1;
        iIndex += 1;
        //kGlobalIndex += 1;
      }

      //for kIndex in kIndex_range do {
      //while ((kIndex < KERNEL_Q_K_ELEMS_PER_GRID) && (iIndex < numK)) {
      while ((kIndex < KERNEL_Q_K_ELEMS_PER_GRID) && (iIndex < numK)) {
        const expArg = PIx2 : real(32) * (constMem(kIndex).Kx * sX + constMem(kIndex).Ky * sY + constMem(kIndex).Kz * sZ);
        var phiMag_scalar = constMem(kIndex).PhiMag;
        sQr += phiMag_scalar * cos(expArg);
        sQi += phiMag_scalar * sin(expArg);

        const kIndex1 = kIndex + 1;
        const expArg1 = PIx2 : real(32) * (constMem(kIndex1).Kx * sX + constMem(kIndex1).Ky * sY + constMem(kIndex1).Kz * sZ);
        const phiMag_scalar1 = constMem(kIndex1).PhiMag;
        sQr += phiMag_scalar1 * cos(expArg1);
        sQi += phiMag_scalar1 * sin(expArg1);

        kIndex += 2;
        iIndex += 2;
        //kGlobalIndex += 2;
      }
      (Qr(xIndex), Qi(xIndex)) = (sQr, sQi);
    }
if timing then timer.stop();
if timing then totaltime += timer.elapsed();
if timing then timer.clear();

  }

  for i in 0..99 do
    write(Qr(i), " ");

if timing then writeln("total gpu time = ", totaltime);
//writeln("Qr = ", Qr);

  outfile = fopen(outfilename, "wb");
  outputData(outfile, numX, Qr, Qi);
  fclose(outfile);
}
