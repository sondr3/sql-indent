;;; sql-indent.el --- indentation of SQL statements

;; Copyright (C) 2000  Alex Schroeder

;; Authors: Alex Schroeder <alex@gnu.org>
;;          Matt Henry <mcthenry+gnu@gmail.com>
;; Maintainer: Boerge Svingen <bsvingen@borkdal.com>
;; Version: 0

;; Keywords: languages
;; URL: https://github.com/bsvingen/sql-indent

;; This file is not part of GNU Emacs.

;; This is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Indent SQL statements.

;; As the indentation of SQL statements depends not only on the previous
;; line but also on the current line, empty lines cannot always be
;; indented correctly.

;; Usage note: Loading this file will make all SQL mode buffers created
;; from then on use `sql-indent-line' for indentation.  A possible way
;; to install sql-indent.el would be to add the following to your
;; .emacs:

;; (eval-after-load "sql"
;;   '(load-library "sql-indent"))

;; Thanks:
;; Arcady Genkin <antipode@thpoon.com>

;;; History:
;; 2018-02-11
;;     * sondr3
;;         Fixed some strange indentation and hanging parenthesis'
;; 2017-03-08
;;     * yangyingchao
;;         Updated `sql-indent-level-delta' logic
;;         Updated `sql-indent-first-column-regexp' syntax
;; 2017-01-15
;;     * davidshepherd7
;;         Made it into a minor mode instead of a hook
;; 2009-03-22*
;;     * mhenry
;;         Added `sql-indent-buffer' for efficient full buffer processing.
;;         Modified `sql-indent' to be savvy to comments and strings.
;;         Removed "and", "or" and "exists" from `sql-indent-first-column-regexp'
;;         Added "create", "drop" and "truncate" to `sql-indent-first-column-regexp'

;;; Code:

(require 'sql)

;; Need the following to allow GNU Emacs 19 to compile the file.
(require 'regexp-opt)

(defcustom sql-indent-first-column-regexp
  (rx (*? space)
      (or "select" "update" "insert" "delete" "union" "intersect" "from"
          "where" "into" "group" "having" "order" "set"
          "use" "alter" "create" "drop" "truncate" "begin" "else"
          "end" ")" "delimiter" "source")
      (or eol space))
  "Regexp matching keywords relevant for indentation.
The regexp matches lines which start SQL statements and it matches lines
that should be indented at the same column as the start of the SQL
statement.  The regexp is created at compile-time.  Take a look at the
source before changing it.  All lines not matching this regexp will be
indented by `sql-indent-offset'."
  :type 'regexp
  :group 'SQL)

(defcustom sql-indent-offset 4
  "*Offset for SQL indentation."
  :type 'number
  :group 'SQL)


(defvar sql-indent-debug nil
  "If non-nil, `sql-indent-line' will output debugging messages.")

(defun sql-indent-is-string-or-comment ()
  "Return nil if point is not in a comment or string; non-nil otherwise."
  (let ((parse-state (syntax-ppss)))
    (or (nth 3 parse-state)             ; String
	      (nth 4 parse-state))))          ; Comment

(defun sql-indent-level-delta (&optional prev-start prev-indent)
  "Calculate the change in level from the previous non-blank line.
Given the optional parameter `PREV-START' and `PREV-INDENT', assume that to be
the previous non-blank line.
Return a list containing the level change and the previous indentation."

  (save-excursion
    ;; Go back to the previous non-blank line
    (let* ((p-line (cond ((and prev-start prev-indent)
			                    (list prev-start prev-indent))
			                   ((sql-indent-get-last-line-start))))
	         (curr-start (point-at-bol))
	         (paren (nth 0 (parse-partial-sexp (nth 0 p-line) curr-start)))
           (result
            ;; Add opening or closing parens.
            ;; If the current line starts with a keyword statement (e.g. SELECT,
            ;;    FROM, ...)  back up one level
            ;; If the previous line starts with a keyword statement then add one level
            (list (+ paren
                     (if (progn (goto-char (nth 0 p-line))
                                (looking-at sql-indent-first-column-regexp)) 1 0)
                     (if (progn (goto-char curr-start)
                                (looking-at sql-indent-first-column-regexp)) -1 0))
                  (nth 1 p-line))))

      (save-excursion
        (goto-char (point-at-bol))

        ;; Cases to increase indent level.
        (when (and (< (car result) 1)
                   (looking-back
                    (rx (or "THEN" "(") (* space) "
") nil))
          (setf (car result) (1+ (car result))))

        ;; Cases to decrease indent level.
        (when (and (>= (car result) 0)
                   (or (looking-at-p (rx (* space) (or ")" "--" "#")))))
          (setf (car result) (1- (car result)))))
      result)))

(defun sql-indent-buffer ()
  "Indent the buffer's SQL statements."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (/= (point) (point-max))
	    (forward-line)
	    (sql-indent-line)
      (end-of-line))))

(defun sql-indent-line ()
  "Indent current line in an SQL statement."
  (interactive)
  (let* ((pos (- (point-max) (point)))
         (beg (progn (beginning-of-line) (point)))

	       (indent-info (sql-indent-level-delta))
	       (level-delta (nth 0 indent-info))
	       (prev-indent (nth 1 indent-info))
	       (this-indent (max 0           ; Make sure the indentation is at least 0
			                     (+ prev-indent
			                        (* sql-indent-offset
				                         (nth 0 indent-info))))))

    (if sql-indent-debug (message "SQL Indent: line: %3d, level delta: %3d; prev: %3d; this: %3d"
		                              (line-number-at-pos) level-delta prev-indent this-indent))
    (skip-chars-forward " \t")
    (indent-line-to this-indent)
    ;; If initial point was within line's indentation,
    ;; position after the indentation. Else stay at the same point in text.
    (if (> (- (point-max) pos) (point))
        (goto-char (- (point-max) pos)))))


(define-minor-mode sql-indent-mode
  "A minor mode enabling more intelligent sql indentation"
  :lighter " SIN"
  :global nil

  ;; body
  (when sql-indent-mode
    (make-local-variable 'indent-line-function)
    (setq indent-line-function 'sql-indent-line))

  (unless sql-indent-mode
    (kill-local-variable 'indent-line-function)))

(provide 'sql-indent)

;;; sql-indent.el ends here
