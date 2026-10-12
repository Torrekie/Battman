#ifndef BAStatisticsMath_h
#define BAStatisticsMath_h

#include <math.h>
#include <stdbool.h>
#include <stddef.h>

/* Pure helpers only: the caller supplies a clipped, trusted sampled pair.
 * Never call these across a gap, a configuration boundary or overlapping
 * source coverage. Linear interpolation is an estimate within that pair. */
typedef struct {
    double seconds[5];             /* [0,20), [20,40), ... [80,100] */
    double jointSeconds[4][5];     /* <25, [25,30), [30,35), >=35 deg C */
    double socCoveredSeconds;
    double jointCoveredSeconds;
} BAStatisticsDwellTotals;

static inline bool BAStatisticsValidSOC(double soc)
{
    return isfinite(soc) && soc >= 0.0 && soc <= 100.0;
}

static inline unsigned BAStatisticsSOCBin(double soc)
{
    return soc < 20.0 ? 0 : soc < 40.0 ? 1 : soc < 60.0 ? 2 : soc < 80.0 ? 3 : 4;
}

static inline unsigned BAStatisticsTemperatureBin(double temperature)
{
    return temperature < 25.0 ? 0 : temperature < 30.0 ? 1 : temperature < 35.0 ? 2 : 3;
}

static inline void BAStatisticsInsertSplit(double *splits, size_t *count, double fraction)
{
    if (!(fraction > 0.0 && fraction < 1.0) || !isfinite(fraction)) return;
    size_t position = 0;
    while (position < *count && splits[position] < fraction) ++position;
    if (position < *count && splits[position] == fraction) return;
    for (size_t i = *count; i > position; --i) splits[i] = splits[i - 1];
    splits[position] = fraction;
    ++*count;
}

/* Returns false without changing totals when SOC or duration is unavailable.
 * A missing/invalid temperature still contributes to SOC-only coverage, but
 * never to a joint bin. Endpoints must have independently validated units. */
static inline bool BAStatisticsAccumulateDwell(BAStatisticsDwellTotals *totals,
                                               double seconds,
                                               double startSOC,
                                               double endSOC,
                                               bool hasTemperature,
                                               double startTemperature,
                                               double endTemperature)
{
    if (!totals || !isfinite(seconds) || seconds <= 0.0 ||
        !BAStatisticsValidSOC(startSOC) || !BAStatisticsValidSOC(endSOC)) return false;

    const bool jointValid = hasTemperature && isfinite(startTemperature) && isfinite(endTemperature);
    const double socChange = endSOC - startSOC;
    const double temperatureChange = jointValid ? endTemperature - startTemperature : 0.0;
    /* Two endpoints plus four SOC and three temperature boundaries. */
    double splits[9] = { 0.0, 1.0 };
    size_t count = 2;
    if (socChange != 0.0) {
        for (unsigned boundary = 20; boundary <= 80; boundary += 20)
            BAStatisticsInsertSplit(splits, &count, ((double)boundary - startSOC) / socChange);
    }
    if (jointValid && temperatureChange != 0.0) {
        for (unsigned boundary = 25; boundary <= 35; boundary += 5)
            BAStatisticsInsertSplit(splits, &count, ((double)boundary - startTemperature) / temperatureChange);
    }
    for (size_t i = 1; i < count; ++i) {
        const double midpoint = (splits[i - 1] + splits[i]) * 0.5;
        const double duration = (splits[i] - splits[i - 1]) * seconds;
        const unsigned socBin = BAStatisticsSOCBin(startSOC + socChange * midpoint);
        totals->seconds[socBin] += duration;
        if (jointValid) {
            const unsigned temperatureBin = BAStatisticsTemperatureBin(startTemperature + temperatureChange * midpoint);
            totals->jointSeconds[temperatureBin][socBin] += duration;
        }
    }
    totals->socCoveredSeconds += seconds;
    if (jointValid) totals->jointCoveredSeconds += seconds;
    return true;
}

/* Boundary estimates stay inside this trusted ascending adjacent pair. Flat
 * or downward pairs do not establish an upward crossing. */
static inline bool BAStatisticsUpwardCrossingFraction(double startSOC,
                                                      double endSOC,
                                                      double boundary,
                                                      double *fraction)
{
    if (!fraction || !BAStatisticsValidSOC(startSOC) || !BAStatisticsValidSOC(endSOC) ||
        !BAStatisticsValidSOC(boundary) || !(endSOC > startSOC) ||
        boundary < startSOC || boundary > endSOC) return false;
    *fraction = (boundary - startSOC) / (endSOC - startSOC);
    return true;
}

typedef struct {
    size_t count;
    bool hasBox;
    double minimum;
    double firstQuartile;
    double median;
    double thirdQuartile;
    double maximum;
} BAStatisticsQuantiles;

static inline double BAStatisticsMedianOfSortedValues(const double *values, size_t count)
{
    if (!values || count == 0) return NAN;
    return count % 2 ? values[count / 2] : values[count / 2 - 1] * 0.5 + values[count / 2] * 0.5;
}

/* Values must be finite and sorted ascending. Whiskers are observed min/max.
 * For odd n, the central observation is excluded from both quartile halves.
 * n < 3 has no box: Q1 and Q3 stay unavailable rather than inventing a range. */
static inline BAStatisticsQuantiles BAStatisticsQuantilesForSortedValues(const double *values,
                                                                         size_t count)
{
    BAStatisticsQuantiles result = { 0, false, NAN, NAN, NAN, NAN, NAN };
    if (!values || count == 0) return result;
    for (size_t i = 0; i < count; ++i)
        if (!isfinite(values[i]) || (i && values[i] < values[i - 1])) return result;
    result.count = count;
    result.minimum = values[0];
    result.maximum = values[count - 1];
    result.median = BAStatisticsMedianOfSortedValues(values, count);
    if (count >= 3) {
        const size_t halfCount = count / 2;
        result.hasBox = true;
        result.firstQuartile = BAStatisticsMedianOfSortedValues(values, halfCount);
        result.thirdQuartile = BAStatisticsMedianOfSortedValues(values + count - halfCount, halfCount);
    }
    return result;
}

#endif /* BAStatisticsMath_h */
