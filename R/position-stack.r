#' Stack overlapping objects on top of one another.
#'
#' \code{position_stack} stacks bars on top of each other; \code{position_fill}
#' additionally standardises each stack to have constant height.
#'
#' \code{position_fill} and \code{position_stack} automatically stacks
#' values so their order follows the decreasing sort order of the fill
#' aesthetic. This makes sure that the stack order is aligned with the order in
#' the legend, as long as the scale order has not been changed using the
#' \code{breaks} argument. This also means that in order to change stacking
#' order while preserving parity with the legend order it is necessary to
#' reorder the factor levels of the fill aesthetic (see examples)
#'
#' Stacking of positive and negative values are performed separately so that
#' positive values stack upwards from the x-axis and negative values stack
#' downward. Do note that parity with legend order cannot be ensured when
#' positive and negative values are mixed.
#'
#' @family position adjustments
#' @param vjust Vertical adjustment for geoms that have a position
#'   (like points or lines), not a dimension (like bars or areas). Set to
#'   \code{0} to align with the bottom, \code{0.5} for the middle,
#'   and \code{1} (the default) for the top.
#' @seealso See \code{\link{geom_bar}}, and \code{\link{geom_area}} for
#'   more examples.
#' @export
#' @examples
#' # Stacking and filling ------------------------------------------------------
#'
#' # Stacking is the default behaviour for most area plots.
#' # Fill makes it easier to compare proportions
#' ggplot(mtcars, aes(factor(cyl), fill = factor(vs))) +
#'   geom_bar()
#' ggplot(mtcars, aes(factor(cyl), fill = factor(vs))) +
#'   geom_bar(position = "fill")
#'
#' ggplot(diamonds, aes(price, fill = cut)) +
#'   geom_histogram(binwidth = 500)
#' ggplot(diamonds, aes(price, fill = cut)) +
#'   geom_histogram(binwidth = 500, position = "fill")
#'
#' # Stacking is also useful for time series
#' series <- data.frame(
#'   time = c(rep(1, 4),rep(2, 4), rep(3, 4), rep(4, 4)),
#'   type = rep(c('a', 'b', 'c', 'd'), 4),
#'   value = rpois(16, 10)
#' )
#' ggplot(series, aes(time, value)) +
#'   geom_area(aes(fill = type))
#'
#' # Stacking order ------------------------------------------------------------
#'
#' # You control the stacking order by setting the levels of the underlying
#' # factor. See the forcats package for convenient helpers.
#' series$type2 <- factor(series$type, levels = c('c', 'b', 'd', 'a'))
#' ggplot(series, aes(time, value)) +
#'   geom_area(aes(fill = type2))
#'
#' # You can change the order of the levels in the legend using the scale
#' ggplot(series, aes(time, value)) +
#'   geom_area(aes(fill = type)) +
#'   scale_fill_discrete(breaks = c('a', 'b', 'c', 'd'))
#'
#' # Non-area plots ------------------------------------------------------------
#'
#' # When stacking across multiple layers it's a good idea to always set
#' # the `group` aethetic in the ggplot() call. This ensures that all layers
#' # are stacked in the same way.
#' ggplot(series, aes(time, value, group = type)) +
#'   geom_line(aes(colour = type), position = "stack") +
#'   geom_point(aes(colour = type), position = "stack")
#'
#' ggplot(series, aes(time, value, group = type)) +
#'   geom_area(aes(fill = type)) +
#'   geom_line(aes(group = type), position = "stack")
#'
#' # You can also stack labels, but the default position is suboptimal.
#' ggplot(series, aes(time, value, group = type)) +
#'   geom_area(aes(fill = type)) +
#'   geom_text(aes(label = type), position = "stack")
#'
#' # You can override this with the vjust parameter. A vjust of 0.5
#' # will center the labels inside the corresponding area
#' ggplot(series, aes(time, value, group = type)) +
#'   geom_area(aes(fill = type)) +
#'   geom_text(aes(label = type), position = position_stack(vjust = 0.5))
#'
#' # Negative values -----------------------------------------------------------
#'
#' df <- tibble::tribble(
#'   ~x, ~y, ~grp,
#'   "a", 1,  "x",
#'   "a", 2,  "y",
#'   "b", 1,  "x",
#'   "b", 3,  "y",
#'   "b", -1, "y"
#' )
#' ggplot(data = df, aes(x, y, group = grp)) +
#'   geom_col(aes(fill = grp)) +
#'   geom_hline(yintercept = 0)
#'
#' ggplot(data = df, aes(x, y, group = grp)) +
#'   geom_col(aes(fill = grp)) +
#'   geom_hline(yintercept = 0) +
#'   geom_text(aes(label = grp), position = position_stack(vjust = 0.5))
position_stack <- function(vjust = 1) {
  ggproto(NULL, PositionStack, vjust = vjust)
}

#' @export
#' @rdname position_stack
position_fill <- function(vjust = 1) {
  ggproto(NULL, PositionFill, vjust = vjust)
}

#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
PositionStack <- ggproto("PositionStack", Position,
  type = NULL,
  vjust = 1,
  fill = FALSE,

  setup_params = function(self, data) {
    list(
      var = self$var %||% stack_var(data),
      fill = self$fill,
      vjust = self$vjust
    )
  },

  setup_data = function(self, data, params) {
    if (is.null(params$var)) {
      return(data)
    }

    data$ymax <- switch(params$var,
      y = data$y,
      ymax = ifelse(data$ymax == 0, data$ymin, data$ymax)
    )

    remove_missing(
      data,
      vars = c("x", "xmin", "xmax", "y"),
      name = "position_stack"
    )
  },

  compute_panel = function(data, params, scales) {
    if (is.null(params$var)) {
      return(data)
    }

    negative <- data$ymax < 0
    neg <- data[negative, , drop = FALSE]
    pos <- data[!negative, , drop = FALSE]

    if (any(negative)) {
      # Negate group so sorting order is consistent across the x-axis.
      # Undo negation afterwards so it doesn't mess up the rest
      neg$group <- -neg$group
      neg <- collide(neg, NULL, "position_stack", pos_stack,
        vjust = params$vjust,
        fill = params$fill
      )
      neg$group <- -neg$group
    }

    if (any(!negative)) {
      pos <- collide(pos, NULL, "position_stack", pos_stack,
        vjust = params$vjust,
        fill = params$fill
      )
    }

    rbind(neg, pos)
  }
)

pos_stack <- function(df, width, vjust = 1, fill = FALSE) {
  n <- nrow(df) + 1
  y <- ifelse(is.na(df$y), 0, df$y)
  heights <- c(0, cumsum(y))

  if (fill) {
    heights <- heights / abs(heights[length(heights)])
  }

  df$ymin <- pmin(heights[-n], heights[-1])
  df$ymax <- pmax(heights[-n], heights[-1])
  df$y <- (1 - vjust) * df$ymin + vjust * df$ymax
  df
}


#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
PositionFill <- ggproto("PositionFill", PositionStack,
  fill = TRUE
)

stack_var <- function(data) {
  if (!is.null(data$ymax)) {
    if (any(data$ymin != 0 && data$ymax != 0, na.rm = TRUE)) {
      warning("Stacking not well defined when not anchored on the axis", call. = FALSE)
    }
    "ymax"
  } else if (!is.null(data$y)) {
    "y"
  } else {
    warning(
      "Stacking requires either ymin & ymin or y aesthetics.\n",
      "Maybe you want position = 'identity'?",
      call. = FALSE
    )
    NULL
  }
}
