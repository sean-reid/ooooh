# Policy

Fits the speak decision as a logistic regression over the checks the eval writes, and measures it against the shipped governor on sessions it never saw. Nothing to install; it runs on Node's standard library.

First write the rows. `--features` takes a corpus or one fixture, replays the recorded answers, and writes one CSV row per check: the loop's signals, every number Jev gave, what the governor decided, and the label the scorer would give a prompt at that moment (`speak` with its kind, `leave`, `finished`, or `wait`). The label comes from the scorer's own code, so the CSV and the CI gate agree on what a hit is.

```
swift run --package-path Packages eval --corpus data/recordings --answers-dir data/recordings/answers --features /tmp/policy/real.csv
swift run --package-path Packages eval --corpus fixtures/synthetic/estimate --answers-dir fixtures/synthetic/estimate/answers --features /tmp/policy/synthetic.csv
node tools/policy/policy.mjs fit /tmp/policy/real.csv
node tools/policy/policy.mjs evaluate /tmp/policy/real.csv /tmp/policy/synthetic.csv
```

`fit` standardises the 15 features (the five cue probabilities, goodMoment, seemsFinished, momentum, articulation, pauseLength, speechDensity, log seconds since the start, log seconds since the last prompt capped at 300, promptsSoFar, wordsSoFar), fits speak against everything else with L2 regularisation by full-batch gradient descent, and prints the weights in standardised and raw form. `--lambda` sets the penalty, 1 by default. `evaluate` leaves one session out at a time: fit on the rest, take the threshold that reaches `--recall` (0.45) on the training rows, score the held-out session, and print precision, recall, and intrusions per fold and pooled beside the governor's decisions on the same checks. Several CSVs pool into one run.

The numbers are per check, not per spoken prompt. A labeled moment covers every check inside the tolerance, and a decision that arming would have cancelled still counts, so they sit apart from the gate's figures.

The model stays linear. There are about a hundred real checks and a dozen positives, which is too few for anything that cannot be read off a table, and a logit over 15 weights ports to Swift in a dozen lines and ships as config.

`node --test tools/policy/*.test.mjs` runs without a CSV.
