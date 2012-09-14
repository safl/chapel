//
// Use standard modules for Block distributions and Timing routines
//
use BlockDist, Time;

//
// Use the user modules for computing HPCC problem sizes and for
// defining RA's random stream of values
//
use HPCCProblemSize, RARandomStream;

//
// The number of tables as well as the element and index types of
// that table
//
const numTables = 1;
type elemType = randType,
     indexType = randType;

//
// Configuration constants defining log2(problem size) -- n -- and
// the number of updates -- N_U
//
config const n = computeProblemSize(numTables, elemType,
                                    returnLog2=true, retType=indexType),
             N_U = 2**(n+2);

//
// Constants defining the problem size (m) and a bit mask for table
// indexing
//
const m = 2**n,
      indexMask = m-1;

//
// Unless we protect against it, the verification pass can get wrong
// answers due to races in the same way that the main computation can.
// This can lead to a total error count that exceeds the threshold,
// causing a spurious failure report.  We protect against errors in
// verification by using sync variables to single-thread accesses to
// blocks of table elements, with no more than verifyBlockSize elements
// per block.  As a rule of thumb, verifyBlockSize should be chosen such
// that there are a few times as many blocks (thus sync variables) as
// the maximum number of tasks that could actually be running at any one
// time.  The "few times" multiplier, named coreConcurrencyFactor here,
// accounts for two effects.  One is that task switching during critical
// sections can make it seem as though more tasks are competing for
// access to those critical sections than there are hardware cores.  The
// other is that a smaller block size reduces the likelihood that two
// tasks will try to work on table elements in the same block at the
// same time.  Of course, reducing the protection block size increases
// the number of protection blocks and thus the amount of memory needed
// for sync variables.  So we have the classic tradeoff: using a higher
// coreConcurrencyFactor increases performance because it reduces the
// number of single-threading conflicts, but it means that the program
// requires more memory.  Here we set coreConcurrencyFactor to 4 by
// default, but that value was chosen intuitively rather than as a
// result of careful study.
//
config const coreConcurrencyFactor = 4;
config const verifyBlockSize = m / (numLocales
                                    * here.numCores
                                    * coreConcurrencyFactor):indexType;

//
// Configuration constant defining the number of errors to allow (as a
// fraction of the number of updates, N_U)
//
config const errorTolerance = 1e-2;

//
// Configuration constants to control what's printed -- benchmark
// parameters, input and output arrays, and/or statistics
//
config const printParams = true,
             printArrays = false,
             printStats = true;

//
// TableDist is a 1D block distribution for domains storing indices
// of type "indexType", and it is computed by blocking the bounding
// box 0..m-1 across the set of locales.  UpdateDist is a similar
// distribution that is computed by blocking the indices 0..N_U-1
// across the locales.
//
const TableDist = new dmap(new Block(boundingBox={0..m-1})),
      UpdateDist = new dmap(new Block(boundingBox={0..N_U-1}));

//
// TableSpace describes the index set for the table.  It is a 1D
// domain storing indices of type indexType, it is distributed
// according to TableDist, and it contains the indices 0..m-1.
// Updates is an index set describing the set of updates to be made.
// It is distributed according to UpdateDist and contains the
// indices 0..N_U-1.
//
const TableSpace: domain(1, indexType) dmapped TableDist = {0..m-1},
      Updates: domain(1, indexType) dmapped UpdateDist = {0..N_U-1};


//
// The program entry point
//
proc main() {
  //
  // T is the distributed table itself, storing a variable of type
  // elemType for each index in TableSpace.
  //
  var T: [TableSpace] elemType;

  printConfiguration();   // print the problem size, number of trials, etc.

  //
  // In parallel, initialize the table such that each position
  // contains its index.  "[i in TableSpace]" is shorthand for "forall
  // i in TableSpace"
  //
  [i in TableSpace] T(i) = i;

  const startTime = getCurrentTime();              // capture the start time

  //
  // The main computation: Iterate over the set of updates and the
  // stream of random values in a parallel, zippered manner, dropping
  // the update index on the ground and storing the random value
  // in r.  Use an on-clause to force the table update to be executed on
  // the locale which owns the table element in question to minimize
  // communications.  Compute the update using r both to compute the
  // index and as the update value.
  //
  forall (_, r) in zip(Updates, RAStream()) do
    on T(r & indexMask) do
      T(r & indexMask) ^= r;

  const execTime = getCurrentTime() - startTime;   // capture the elapsed time

  const validAnswer = verifyResults(T);            // verify the updates
  printResults(validAnswer, execTime);             // print the results
}

//
// Print the problem size and number of updates
//
proc printConfiguration() {
  if (printParams) {
    if (printStats) then printLocalesTasks();
    printProblemSize(elemType, numTables, m);
    writeln("Number of updates = ", N_U, "\n");
  }
}

//
// Verify that the computation is correct
//
proc verifyResults(T) {
  //
  // We protect against errors in verification by using sync variables
  // to protect accesses to blocks of table elements.  The configuration
  // constant verifyBlockSize is the initial, user adjustable, setting
  // of the size of a protection block.  Its actual size is the largest
  // power of 2 less than or equal to verifyBlockSize.  This allows us
  // to use an inexpensive mask operation to compute the strided sync
  // var array index that corresponds to a given table index.  It may
  // also cause us to use more memory for sync variables than we would
  // if we used verifyBlockSize directly, but if so it will also provide
  // more conflict avoidance.
  //
  const lockStride = if verifyBlockSize < 1
                     then 1
                     else 2 ** log2(verifyBlockSize),
        lockIndexMask = indexMask & ~(lockStride - 1);
  const lockSpace = TableSpace by lockStride;
  var locks$: [lockSpace] sync bool;

  //
  // Print the table, if requested
  //
  if (printArrays) then writeln("After updates, T is: ", T, "\n");

  //
  // Reverse the updates by recomputing them, this time using sync
  // variables to ensure no conflicting updates.
  //
  forall (_, r) in zip(Updates, RAStream()) do
    on T(r & indexMask) do {
      locks$(r & lockIndexMask) = true;
      T(r & indexMask) ^= r;
      locks$(r & lockIndexMask);
    }

  //
  // Print the table again after the updates have been reversed
  //
  if (printArrays) then writeln("After verification, T is: ", T, "\n");

  //
  // Compute the number of table positions that weren't reverted
  // correctly.  This is an indication of the number of conflicting
  // updates.
  //
  const numErrors = + reduce [i in TableSpace] (T(i) != i);
  if (printStats) then writeln("Number of errors is: ", numErrors, "\n");

  //
  // Return whether or not the number of errors was within the benchmark's
  // tolerance.
  //
  return numErrors <= (errorTolerance * N_U);
}

//
// Print out success/failure, the execution time, and the GUPS value
//
proc printResults(successful, execTime) {
  writeln("Validation: ", if successful then "SUCCESS" else "FAILURE");
  if (printStats) {
    writeln("Execution time = ", execTime);
    writeln("Performance (GUPS) = ", (N_U / execTime) * 1e-9);
  }
}
