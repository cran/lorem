#' Generate Lorem Ipsum Text
#'
#' @description
#' Generates _lorem ipsum_ placeholder text for the requested number of
#' sentences or paragraphs. You can control the number of sentences per
#' paragraph and the average number of words per sentence, or simply enter the
#' number of desired paragraphs for a completely random experience.
#'
#' `lorem::ipsum()` uses sampling and the random number generator and makes no
#' effort to shield the placeholder text generation from the main script, so
#' please only use this package for temporary placeholder text.
#'
#' @section Options:
#'
#'   You can influence, to a degree, the amount of punctuation that is included
#'   in the output using the `lorem.punctuation_valence` option. This global
#'   option should be a number between 0 and 1, or `FALSE` to disable
#'   punctuation altogether. When the value is closer to 1, more punctuation is
#'   included in the sentences. When the value is closer to 0, less punctuation
#'   will be inserted. The default value is 0.4.
#'
#' @examples
#' # 1 paragraph of text
#' lorem::ipsum(1)
#'
#' # 2 paragraphs with 2 and 3 sentences each
#' lorem::ipsum(2, sentences = c(2, 3))
#'
#' # 2 paragraphs with short sentences
#' lorem::ipsum(2, avg_words_per_sentence = 4)
#'
#' # 2 paragraphs with long sentences
#' lorem::ipsum(2, avg_words_per_sentence = 20)
#'
#' @return A character vector of _lorem ispum_ placeholder text, where each
#'   element in the vector is a paragraph of text.
#'
#' @param paragraphs Number of paragraphs of text to generate.
#' @param sentences Number of sentences per paragraph. If `NULL`, then a random
#'   number of sentences per paragraph (approximately 3-8) will be chosen.
#'   Alternatively, `sentences` can be a vector of integers representing the
#'   number of sentences per paragraph.
#' @param avg_words_per_sentence Number of expected words per sentence.
#' @name ipsum
NULL

#' @describeIn ipsum Generate paragraphs and sentences of _lorem ipsum_ text.
#' @export
ipsum <- function(paragraphs = 1, sentences = NULL, avg_words_per_sentence = 10) {
  # default to single paragraph
  paragraphs <- paragraphs %||% 1L
  stopifnot(
    "`paragraphs` must be a single integer" = length(paragraphs) == 1,
    "`paragraphs` must be an integer" = paragraphs %% 1 == 0,
    "`paragraphs` must be greater than 0" = paragraphs > 0,
    "`paragraphs` must be finite" = is.finite(paragraphs)
  )

  # Pick number of sentences to be about 3-8
  if (!is.null(sentences)) {
    stopifnot(
      "`sentences` must be a vector of finite values" = all(is.finite(sentences)),
      "`sentences` must be a vector of integer values" = all(sentences %% 1 == 0),
      "`sentences` must be a vector of 1 or more integers greater than zero" = all(sentences > 0)
    )
  } else {
    sentences <- stats::rbinom(paragraphs, 10, 0.45)
    sentences[sentences < 1] <- 1L
  }

  if (length(sentences) == 1 && paragraphs > 1) {
    sentences <- rep(sentences, paragraphs)
  }

  if (paragraphs != length(sentences)) {
    stop(
      "`sentences` must be a single integer ",
      "or have the same length as the number of `paragraphs`."
    )
  }

  # check punctuation valence so we can warn about bad values
  get_punctuation_valence(warn = TRUE)

  # roughly 10 words per sentence per paragraph
  words <- stats::rbinom(paragraphs, avg_words_per_sentence * sentences * 2, 0.5)

  # generate words
  text <- v_char(1:paragraphs, function(i) ipsum_words(words[i]))
  text <- paste(ipsum_starts(paragraphs), text)

  # break into sentences
  ret <- pv_char(break_sentences, text = text, n = sentences)
  structure(as.list(ret), class = "lorem")
}

#' @describeIn ipsum Generate _lorem ipsum_ words, without punctuation.
#' @param n Number of words to generate
#' @param collapse Should the words be collapsed into a single string, separated
#'   by spaces (default)? If `FALSE`, the chosen words are returned as a
#'   character vector.
#' @export
ipsum_words <- function(n, collapse = TRUE) {
  words <- sample(words$word, n, replace = TRUE)
  if (collapse) paste(words, collapse = " ") else words
}

#' @describeIn ipsum Generate _lorem ipsum_ starting words.
#' @export
ipsum_starts <- function(n) {
  sample(words$start, n, replace = TRUE)
}

break_sentences <- function(text, n = NULL) {
  n <- n %||% default_n_sentences(text)

  v_char(text, break_sentence, n = n)
}

break_sentence <- function(text, n) {
  if (n == 1) {
    return(as_sentence(text))
  }

  # sentences of approx 10 words each
  words <- stats::rbinom(n = n - 1, 20, 0.5)
  text <- strsplit(text, " ", fixed = TRUE)[[1]]
  if (words[1] >= length(text)) {
    return(as_sentence(text))
  }
  while (sum(words) > length(text)) {
    longest <- which(words == max(words))[1]
    words[longest] <- words[longest] - 1L
  }
  words <- c(cumsum(words), length(text))

  sentences <- list()
  for (i in seq_along(words)) {
    from <- if (i == 1) 1L else words[i-1] + 1
    to <- words[i]
    subtext <- text[from:to]
    sentences <- c(sentences, list(subtext))
  }
  sentences <- v_char(sentences, as_sentence)
  paste0(sentences, collapse = " ")
}

as_sentence <- function(x) {
  x <- insert_punctuation(x)
  x <- paste(x, collapse = " ")
  x <- to_sentence_case(x)
  ending <- sample(c(".", "!", "?"), 1, prob = c(0.7, 0.15, 0.15))
  paste0(x, ending)
}

insert_punctuation <- function(x) {
  valence <- get_punctuation_valence()
  if (identical(valence, FALSE)) return(x)

  idxs <- seq_along(x)

  # draw at most n_words/3 samples from normal distribution
  r_normal <- stats::rnorm(ceiling(length(x) / 3), mean(idxs), sd = sqrt(length(x)))

  # discard first and last word
  r_normal <- r_normal[r_normal > 2 & r_normal < (length(x) - 2)]

  # keep only the indexes that are within 0.2 of a sample
  within_thresh <- vapply(r_normal, FUN.VALUE = logical(1), function(r) {
    any(abs(r - idxs) < valence / 2)
  })
  idxs <- as.integer(round(r_normal[within_thresh], 0))

  if (!length(idxs)) return(x)

  r_punct <- random_punctuation(length(idxs))

  if (all(c(":", ";") %in% r_punct)) {
    # don't allow both : and ; in the same sentence
    discard <- sample(c(":", ";"), 1)
    r_punct[r_punct == discard] <- ""
  }

  # at most one colon per sentence
  for (colon in c(":", ";")) {
    if (length(r_punct[r_punct == colon]) > 2) {
      idx_colon <- which(r_punct == colon)
      discard_colon <- sample(idx_colon, size = length(idx_colon) - 1)
      r_punct[discard_colon] <- ""
    }
  }

  x[idxs] <- paste0(x[idxs], r_punct)
  x
}

random_punctuation <- function(n) {
  sample(
    x    = c(",", ":", ";", " \u2013"),
    prob = c(0.7, 0.1, 0.1, 0.1),
    size = n,
    replace = TRUE
  )
}

get_punctuation_valence <- function(warn = FALSE) {
  valence <- getOption("lorem.punctuation_valence", 0.4)
  if (identical(valence, FALSE)) return(FALSE)
  if (identical(valence, TRUE)) return(0.4)

  if (!is.numeric(valence) || valence > 1 || valence < 0) {
    if (isTRUE(warn)) {
      warning(
        "The `lorem.punctuation_valence` option should be a numeric value ",
        "between 0 and 1, not ",
        valence,
        ". Using the default value of 0.2.",
        call. = FALSE,
        immediate. = TRUE
      )
    }
    valence <- 0.4
  }
  valence
}

default_n_sentences <- function(text) {
  n_words <- count_words(text)

  x <- round(n_words / 10, 0)
  x[x < 1] <- 1L
  x
}

count_words <- function(x) {
  x <- strsplit(x, " ", fixed = TRUE)
  vapply(x, function(y) length(y), integer(1))
}

to_sentence_case <- function(x) {
  x <- tolower(x)
  first <- v_char(x, function(y) substr(y, 1, 1))
  rest <- v_char(x, function(y) substr(y, 2, nchar(y)))
  first <- toupper(first)
  paste0(first, rest)
}
