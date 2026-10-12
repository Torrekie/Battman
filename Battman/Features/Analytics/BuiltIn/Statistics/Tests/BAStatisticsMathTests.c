#include "../BAStatisticsMath.h"

#include <assert.h>
#include <stdio.h>

static void closeEnough(double actual, double expected)
{
    assert(fabs(actual - expected) <= 1e-9 * fmax(1.0, fabs(expected)));
}

static double totalBins(const BAStatisticsDwellTotals *totals)
{
    double sum = 0.0;
    for (unsigned i = 0; i < 5; ++i) sum += totals->seconds[i];
    return sum;
}

static double totalJoint(const BAStatisticsDwellTotals *totals)
{
    double sum = 0.0;
    for (unsigned row = 0; row < 4; ++row)
        for (unsigned column = 0; column < 5; ++column) sum += totals->jointSeconds[row][column];
    return sum;
}

static void testElapsedWeightingAndMissingFields(void)
{
    BAStatisticsDwellTotals totals = { 0 };
    assert(BAStatisticsAccumulateDwell(&totals, 60.0, 10.0, 10.0, false, NAN, NAN));
    assert(BAStatisticsAccumulateDwell(&totals, 540.0, 90.0, 90.0, false, NAN, NAN));
    closeEnough(totals.seconds[0], 60.0);
    closeEnough(totals.seconds[4], 540.0);
    closeEnough(totals.socCoveredSeconds, 600.0);
    closeEnough(totalJoint(&totals), 0.0);

    /* An unknown temperature never becomes zero degrees or a low-temp bin. */
    assert(BAStatisticsAccumulateDwell(&totals, 60.0, 20.0, 20.0, true, NAN, 26.0));
    closeEnough(totals.jointCoveredSeconds, 0.0);
    assert(!BAStatisticsAccumulateDwell(&totals, 60.0, NAN, 90.0, true, 26.0, 26.0));
    assert(!BAStatisticsAccumulateDwell(&totals, 60.0, -1.0, 90.0, true, 26.0, 26.0));
    assert(!BAStatisticsAccumulateDwell(&totals, 0.0, 10.0, 10.0, true, 26.0, 26.0));
    closeEnough(totals.socCoveredSeconds, 660.0);
    closeEnough(totalBins(&totals), 660.0);
}

static void testCrossingSplitsAndInclusiveEdges(void)
{
    BAStatisticsDwellTotals totals = { 0 };
    assert(BAStatisticsAccumulateDwell(&totals, 1000.0, 0.0, 100.0, true, 20.0, 40.0));
    for (unsigned bin = 0; bin < 5; ++bin) closeEnough(totals.seconds[bin], 200.0);
    closeEnough(totals.jointSeconds[0][0], 200.0);
    closeEnough(totals.jointSeconds[0][1], 50.0);
    closeEnough(totals.jointSeconds[1][1], 150.0);
    closeEnough(totals.jointSeconds[1][2], 100.0);
    closeEnough(totals.jointSeconds[2][2], 100.0);
    closeEnough(totals.jointSeconds[2][3], 150.0);
    closeEnough(totals.jointSeconds[3][3], 50.0);
    closeEnough(totals.jointSeconds[3][4], 200.0);
    closeEnough(totalJoint(&totals), 1000.0);
    closeEnough(totals.jointCoveredSeconds, 1000.0);

    BAStatisticsDwellTotals reverse = { 0 };
    assert(BAStatisticsAccumulateDwell(&reverse, 1000.0, 100.0, 0.0, true, 40.0, 20.0));
    for (unsigned row = 0; row < 4; ++row)
        for (unsigned column = 0; column < 5; ++column)
            closeEnough(reverse.jointSeconds[row][column], totals.jointSeconds[row][column]);

    BAStatisticsDwellTotals exact = { 0 };
    assert(BAStatisticsAccumulateDwell(&exact, 60.0, 100.0, 100.0, true, 25.0, 25.0));
    closeEnough(exact.seconds[4], 60.0);
    closeEnough(exact.jointSeconds[1][4], 60.0);
    assert(BAStatisticsAccumulateDwell(&exact, 60.0, 20.0, 20.0, true, 35.0, 35.0));
    closeEnough(exact.seconds[1], 60.0);
    closeEnough(exact.jointSeconds[3][1], 60.0);
}

static void testTrustedCrossingsAndCallerGapExclusion(void)
{
    double fraction = -1.0;
    assert(BAStatisticsUpwardCrossingFraction(10.0, 30.0, 20.0, &fraction));
    closeEnough(fraction, 0.5);
    assert(BAStatisticsUpwardCrossingFraction(20.0, 30.0, 20.0, &fraction));
    closeEnough(fraction, 0.0);
    assert(BAStatisticsUpwardCrossingFraction(70.0, 80.0, 80.0, &fraction));
    closeEnough(fraction, 1.0);
    assert(!BAStatisticsUpwardCrossingFraction(30.0, 10.0, 20.0, &fraction));
    assert(!BAStatisticsUpwardCrossingFraction(20.0, 20.0, 20.0, &fraction));
    assert(!BAStatisticsUpwardCrossingFraction(30.0, 40.0, 20.0, &fraction));
    assert(!BAStatisticsUpwardCrossingFraction(NAN, 30.0, 20.0, &fraction));

    /* Only trusted normalized pairs are passed. The 300-second gap has no
     * synthetic pair and contributes neither dwell time nor joint coverage. */
    const struct { double seconds, startSOC, endSOC; bool trusted; } pairs[] = {
        { 60.0, 10.0, 20.0, true },
        { 300.0, 20.0, 80.0, false },
        { 120.0, 80.0, 90.0, true }
    };
    BAStatisticsDwellTotals totals = { 0 };
    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); ++i)
        if (pairs[i].trusted)
            assert(BAStatisticsAccumulateDwell(&totals, pairs[i].seconds,
                                               pairs[i].startSOC, pairs[i].endSOC,
                                               true, 30.0, 30.0));
    closeEnough(totalBins(&totals), 180.0);
    closeEnough(totalJoint(&totals), 180.0);
    closeEnough(totals.seconds[1], 0.0);
    closeEnough(totals.seconds[2], 0.0);
    closeEnough(totals.seconds[3], 0.0);
}

static void testQuartileConventions(void)
{
    const double odd[] = { 1, 2, 3, 4, 10 };
    BAStatisticsQuantiles q = BAStatisticsQuantilesForSortedValues(odd, 5);
    assert(q.count == 5 && q.hasBox);
    closeEnough(q.minimum, 1);
    closeEnough(q.firstQuartile, 1.5);
    closeEnough(q.median, 3);
    closeEnough(q.thirdQuartile, 7);
    closeEnough(q.maximum, 10);

    const double even[] = { 1, 2, 3, 4, 5, 10 };
    q = BAStatisticsQuantilesForSortedValues(even, 6);
    assert(q.count == 6 && q.hasBox);
    closeEnough(q.firstQuartile, 2);
    closeEnough(q.median, 3.5);
    closeEnough(q.thirdQuartile, 5);
    closeEnough(q.maximum, 10);

    const double three[] = { 1, 3, 9 };
    q = BAStatisticsQuantilesForSortedValues(three, 3);
    assert(q.hasBox);
    closeEnough(q.firstQuartile, 1);
    closeEnough(q.thirdQuartile, 9);
    const double two[] = { 2, 10 };
    q = BAStatisticsQuantilesForSortedValues(two, 2);
    assert(q.count == 2 && !q.hasBox && isnan(q.firstQuartile) && isnan(q.thirdQuartile));
    closeEnough(q.median, 6);
    q = BAStatisticsQuantilesForSortedValues(two, 1);
    assert(q.count == 1 && !q.hasBox && isnan(q.firstQuartile));
    closeEnough(q.minimum, 2);
    closeEnough(q.maximum, 2);
    q = BAStatisticsQuantilesForSortedValues(NULL, 0);
    assert(q.count == 0 && !q.hasBox && isnan(q.median));
    const double unordered[] = { 2, 1, 3 };
    assert(BAStatisticsQuantilesForSortedValues(unordered, 3).count == 0);
    const double unavailable[] = { 1, 2, NAN };
    assert(BAStatisticsQuantilesForSortedValues(unavailable, 3).count == 0);
}

int main(void)
{
    testElapsedWeightingAndMissingFields();
    testCrossingSplitsAndInclusiveEdges();
    testTrustedCrossingsAndCallerGapExclusion();
    testQuartileConventions();
    puts("BAStatisticsMathTests: elapsed weighting, bin crossings, missing/gap exclusion and quartiles passed");
    return 0;
}
