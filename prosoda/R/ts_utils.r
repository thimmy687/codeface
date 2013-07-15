## This file is part of prosoda.  prosoda is free software: you can
## redistribute it and/or modify it under the terms of the GNU General Public
## License as published by the Free Software Foundation, version 2.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
##
## Copyright 2013 by Siemens AG, Wolfgang Mauerer <wolfgang.mauerer@siemens.com>
## All Rights Reserved.

suppressPackageStartupMessages(library(xts))
suppressPackageStartupMessages(library(dtw))

## Omit time series elements that exceed the given range
trim.series <- function(series, start, end) {
  series <- series[which(index(series) < end),]
  series <- series[which(index(series) > start),]

  return(series)
}

## Unidirectional version of the above function
trim.series.start <- function(series, start) {
  return(series[which(index(series) > start),])
}

## Given a series.merged object, extract the data for a particular
## type, and return the result as xts time series
gen.series <- function(series.merged, type) {
  if (type != "Averaged (small window)" &&
      type != "Averaged (large window)" &&
      type != "Cumulative") {
    stop("Internal error: gen.series called with unknown type argument")
  }

  series <- series.merged[series.merged$type==type,]
  return (xts(series$value.scaled, series$time))
}

## Split a time series into per-release-range sub-series
split.by.ranges <- function(series, boundaries) {
  lapply(1:dim(boundaries)[1], function(i) {
    boundaries <- boundaries[i,]
    sub.series <- series[paste(boundaries$date.start, boundaries$date.end, sep="/")]

    return(sub.series)
  })
}

## Compute the distance between two sime series by dynamic time
## warping. Since the computation scales unfavourably with increasing
## series lengths, we down-sample the series if its length exceeds the
## threshold set by MAX.points
compute.ts.distance <- function(series1, series2) {
  MAX.POINTS <- 500
  ## TODO: If we resample the series, we should maybe do this multiple
  ## times, repeat the distance calculation, and compute a agglomerated
  ## result
  if (length(series1) > MAX.POINTS) {
    series1 <- sample(series1, MAX.POINTS)
  }
  if (length(series2) > MAX.POINTS) {
    series2 <- sample(series2, MAX.POINTS)
  }

  ## Handle pathological cases of zero-length time series
  if (xor(length(series1) == 0, length(series2) == 0)) {
    return(1)
  } else if (length(series1) == 0 && length(series2) == 0) {
    return(0)
  }

  return(dtw(series1, series2)$normalizedDistance)
}

## Compute the distance between a specific time series of a project
## for all subsequent releases
compute.release.distance <- function(series.merged, conf) {
  series <- gen.series(series.merged, "Averaged (large window)")
  series <- split.by.ranges(series, conf$boundaries)

  res <- sapply(1:(length(series)-1), function(i) {
    compute.ts.distance(series[[i]], series[[i+1]])
  })
  return(res)
}

## Given a boundaries, check if there are any RC phases present
has.rcs <- function(boundaries) {
  return (sum(!is.na(boundaries$date.rc_start)) > 0)
}

## Give a time series object, return a data frame with t and val
## that contains the time/value pairs of all time series elements.
ts.to.df <- function(time.series) {
  return(data.frame(t=index(time.series), val=coredata(time.series)))
}

## Detrend a time series by fitting a linear model, and subtracting it
## from the original series.
## NOTE: This is somewhat bogous; since the time series usual has considerable
## autocorrelation, the derived model will be inaccurate, and the confidence
## intervals will be too large since the residuals are correlated.
## However, it's unclear how much this matters in practical use.
simple.detrend <- function(s) {
  m <- lm(coredata(s) ~ index(s))

  return(data.frame(t=index(s)[-1], value=coredata(s)[-1],
                    detrend=resid(m)[-1], trend=fitted(m)[-1]))
}

## Perform detrending on a per-range basis
detrend.by.range <- function(s, boundaries) {
  s.split <- split.by.ranges(s, boundaries)

  res <- lapply(s.split, function(s) {
    return(simple.detrend(s))
  })

  res <- do.call(rbind, res)

  return(res)
}