/////////////////////////////////
// make sound for a stage
////////////////////////////////

{|parent, stageName, annotationIdx|

  var sound, group, transpositions, pitches, convertStageName, synths, stageSymbol, fundamental, annotations, bag, qFac, amp;

  sound = parent.sound; // make life easier
  group = ParGroup.after(parent.control.controlGroup); // put a group after all the busses and whatnot
  convertStageName = {|name|
    var symbol;
    switch (name)
      {"SLEEP-S0"} {symbol = \wake}
      {"SLEEP-S1"} {symbol = \stage1}
      {"SLEEP-S2"} {symbol = \stage2}
      {"SLEEP-S3"} {symbol = \stage3}
      {"SLEEP-S4"} {symbol = \stage4}
      {"SLEEP-REM"} {symbol = \stageREM};
    symbol; // return
  };
  stageSymbol = convertStageName.(stageName); // convert the stage name into a usable form
  pitches = sound.at(stageSymbol).pitches; // get the correct pitches for this stage
  // fundamental = parent.control.fundamentalPattern.next; // using a pattern, get a fundamental
  fundamental = 200; // fixed for now
  annotations = parent.annotations;
  parent.currentTasks = List.new(0); // an empty list so it's not nil

  "% ------------------------------------------ % minutes long\n".postf(stageName, (annotations[annotationIdx][1].asFloat/60).round(0.01)); // print the stage name

  ////////////////////////////////////////////////////////
  // if the stage is WAKE
  ////////////////////////////////////////////////////////
  if (stageName == "SLEEP-S0") {
    var env, buff, startFrames;
    "WOKE UP --------------------------".postln;
    env = parent.makeEnv(annotationIdx, true); // make an envelope
    buff = sound.wake.buffers.choose; // pick a buffer to read from
    // better to use a decorrelated sources for the WAKE stages???? Would need to listen to them very carefully
    parent.dream.happened = false; // now we can select a new dream
    parent.dream.prevRem = false; // for checking if we've had REM before. Resets here.
    startFrames = parent.numSpeakers.collect{|i|
      rrand(0, buff.numFrames);
    };


    // play sound
    Synth(\playFile_decorrelate,
      [outBus: 0, buff: buff, amp: -12.dbamp, gate: 1, env: env, startFrames: startFrames],
      target: group
    );
  };

  ////////////////////////////////////////////////////////
  // if it's not WAKE
  ////////////////////////////////////////////////////////
  if (stageName != "SLEEP-S0") {

    // no transpositions for WAKE
    switch (stageName)
      {"SLEEP-S1"} {
        transpositions = [1, 2, 2, 2];
        qFac = 1;
        amp = -9.dbamp;
        fundamental = 200; // 1/1
      }
      {"SLEEP-S2"} {
        transpositions = [1, 2, 2];
        qFac = 0.9;
        amp = -7.dbamp;
        fundamental = 177.7777; // 9/8 down
      }
      {"SLEEP-S3"} {
        transpositions = [0.5, 1, 2, 2];
        qFac = 0.8;
        amp = -5.dbamp;
        fundamental = 175; // 8/7 down
      }
      {"SLEEP-S4"} {
        transpositions = [0.5, 1, 1, 1.5, 2];
        qFac = 0.7;
        amp = -3.dbamp;
        fundamental = 133.3333; // 3/2 down
      }
      {"SLEEP-REM"} {
        transpositions = [0.5, 1, 2, 2, 4];
        qFac = 0.6;
        amp = -7.dbamp;
        fundamental = [200, 177.777, 175, 133.333].choose; // pick one
        parent.dream.prevRem = true;
      };

    bag = Bag.new(); // a Bag of pitches
    pitches = pitches.collect{|fac| bag.add(fac)};
    pitches = bag;

    // actually choose the pitches, make the synths, and play them
    synths = 4.collect{|i|
      // something here with Bag to select pitches
      var pitch, env, kernel, pos;
      pitch = pitches.choose; // choose a pitch at random
      pitches.remove(pitch); // remove that pitch from our possible selection
      pitch = pitch * fundamental; // make it into an actual frequency
      pitch = pitch * transpositions.choose; // transpose it
      env = parent.makeEnv(annotationIdx); // get a unique envelope
      kernel = 2.collect{sound.at(stageSymbol).kernels.choose}; // pick a kernel
      pos = (i-1)*0.5; // get a position
      // "NOT WAKING~~~~~~~~~~~~~~~~~GOT HERE\n".postln;
      "\tpitch: %\n\tenv: %\n\tkernel:%\n\tpos: %\n\n".postf(pitch, env, kernel, pos);
      // defer {env.plot};

      // make a Synth
      Synth(\stageSegment,
        [outBus: 0, kernel: kernel[0], kernel2: kernel[1], freq: pitch, amp: amp, pos: pos, gate: 1, brainBus: parent.control.brainBus, normalizedBrainBus: parent.control.normalizedBrainBus, env: env, qFac: qFac],
        target: group, addAction: \addToTail
      );
    };

    // a Task that periodically changes the kernels
    // this also gives 25% of the same kernels as the last stage for the first 1/3 of the duration of the stage, gradually falling to 0 by 1/3.
    // this also selects whether or not we'll dream.
    Task({
      var lastStage, prob, dur, probDur, firstPass, tmp;

      try {
        lastStage = annotations[annotationIdx-1][0]; // get the last stage. Throws an error if it doesn't exist
        lastStage = convertStageName.(lastStage); // convert it to an appropriate symbol
        prob = [25,100]; // 25% probability if the kernal being from the last stage
        dur = annotations[annotationIdx-1][1].asInteger; // get the duration in seconds
        probDur = (dur/3)/25; // get the incremement in time of 1% of 1/3 of the duration change in prob
        firstPass = true; // this will be the first pass through the dream loop

        ////////////////////////////////////////////////////////////////////////////////
        // independent loop for calculating probability of previous stage kernel being selected
        ////////////////////////////////////////////////////////////////////////////////
        tmp = fork {
          loop {
            probDur.wait; // go by the increment in time of 1% of 1/3 of this duration
            // if we still have a change of selecting a kernel from the previous
            if (prob[0] > 0) {
              prob = [prob[0]-1, prob[1]+1]; // adjust one percent at a time
            };
          };
        };
        parent.currentTasks.add(tmp); // add this fork to the list of tasks

        ////////////////////////////////////////////////////////////////////////////////
        // change the kernals periodically of a random synth
        ////////////////////////////////////////////////////////////////////////////////
        tmp = fork {
          loop {
            var thisSynth, kernels, choice;
            (rrand(1,20)*5).wait; // wait a bit in increments of 5s
            thisSynth = synths.choose; // pick a new synth to change the kernel of
            if (lastStage == \wake) {
              kernels = sound.at(stageSymbol).kernels; // kast stage was WAKE with no kernels
            } {
              kernels = [sound.at(lastStage).kernels, sound.at(stageSymbol).kernels].wchoose(prob.normalizeSum); // choose a set of kernels according to prob
            };
            choice = kernels.choose;
            "\tChanging kernal of % to %\n".postf(thisSynth.nodeID, choice);
            thisSynth.set([\kernel, \kernal2].choose, choice); // pick a new kernel for this synth
            thisSynth.set(\kernelUpdate, 1); // tell it to update
            0.1.wait;
            thisSynth.set(\kernelUpdate, 0); // reset it
          };
        };
        parent.currentTasks.add(tmp); // add this fork to the list of tasks

        ///////////////////////////////////////////////////
        // loop where we decide if we dream or not. And we wait between them, perhaps returning to dream after we're done
        ///////////////////////////////////////////////////
        tmp = fork {
          loop {
            // dream
            var dreamDur;
            // wait 20% of the duration before deciding whether or not we will dream on the first time through
            if (firstPass) {(dur*0.2).wait; firstPass = false};
            dreamDur = parent.dream.decide(stageSymbol, annotationIdx); // decide whether or not we'll dream and return the duration until the next time we check (dream or not)
            (dreamDur*rrand(0.9,1.2)).wait; // wait before we check again
          };
        };
        parent.currentTasks.add(tmp); // add this fork to the list of tasks

      } {|error|
        // if it throws an error, we're at the beginning of the piece (i.e. first stage)
        // same thing with NO PROB
        error.warn;
        "NOT AN ERROR! Piece has begun... If you didn't just start the piece, it's a real error.".postln;
        tmp = loop {
          // change the kernals periodically of a random synth
          var thisSynth;
          (rrand(1,20)*5).wait; // wait a bit in increments of 5s
          thisSynth = synths.choose; // pick a new synth to change the kernel of
          thisSynth.set(\kernel, sound.at(stageSymbol).kernels.choose); // pick a new kernel
          thisSynth.set(\kernelUpdate, 1); // tell it to update
          0.1.wait;
          thisSynth.set(\kernelUpdate, 0); // reset it
        };
        parent.currentTasks.add(tmp); // add this fork to the list of tasks
      };
    }).play; // .PLAY ---------------------------------------------------------------------

  };

  sound.lastGroup = group; // remember this group
}
