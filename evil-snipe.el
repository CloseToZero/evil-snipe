;;; evil-snipe.el --- emulate vim-sneak & vim-seek
;;
;; Copyright (C) 2014-16 Henrik Lissner
;;
;; Author: Henrik Lissner <http://github/hlissner>
;; Maintainer: Henrik Lissner <henrik@lissner.net>
;; Created: December 5, 2014
;; Modified: April 13, 2016
;; Version: 2.0.2
;; Keywords: emulation, vim, evil, sneak, seek
;; Homepage: https://github.com/hlissner/evil-snipe
;; Package-Requires: ((evil "1.0.8") (cl-lib "0.5"))
;;
;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; Evil-snipe emulates vim-seek and/or vim-sneak in evil-mode.
;;
;; It provides 2-character motions for quickly (and more accurately) jumping around
;; text, compared to evil's built-in f/F/t/T motions, incrementally highlighting
;; candidate targets as you type.
;;
;; To enable globally:
;;
;;     (require 'evil-snipe)
;;     (evil-snipe-mode 1)
;;
;; To replace evil-mode's f/F/t/T functionality with (1-character) sniping:
;;
;;     (evil-snipe-override-mode 1)
;;
;; See included README.md for more information.
;;
;;; Code:

(require 'evil)
(eval-when-compile (require 'cl-lib))

(defgroup evil-snipe nil
  "vim-seek/sneak emulation for Emacs"
  :prefix "evil-snipe-"
  :group 'evil)

(defcustom evil-snipe-enable-highlight t
  "If non-nil, all matches will be highlighted after the initial jump.
Highlights will disappear as soon as you do anything afterwards, like move the
cursor."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-enable-incremental-highlight t
  "If non-nil, each additional keypress will incrementally search and highlight
matches. Otherwise, only highlight after you've finished skulking."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-override-evil-repeat-keys t
  "If non-nil (while `evil-snipe-override-evil' is non-nil) evil-snipe will
override evil's ; and , repeat keys in favor of its own."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-scope 'line
  "Dictates the scope of searches, which can be one of:

    'line    ;; search line after the cursor (this is vim-seek behavior) (default)
    'buffer  ;; search rest of the buffer after the cursor (vim-sneak behavior)
    'visible ;; search rest of visible buffer (Is more performant than 'buffer, but
             ;; will not highlight/jump past the visible buffer)
    'whole-line     ;; same as 'line, but highlight matches on either side of cursor
    'whole-buffer   ;; same as 'buffer, but highlight *all* matches in buffer
    'whole-visible  ;; same as 'visible, but highlight *all* visible matches in buffer"
  :group 'evil-snipe
  :type '(choice
          (const :tag "Forward line" 'line)
          (const :tag "Forward buffer" 'buffer)
          (const :tag "Forward visible buffer" 'visible)
          (const :tag "Whole line" 'whole-line)
          (const :tag "Whole buffer" 'whole-buffer)
          (const :tag "Whole visible buffer" 'whole-visible)))

(defcustom evil-snipe-repeat-scope nil
  "Dictates the scope of repeat searches (see `evil-snipe-scope' for possible
settings). When nil, defaults to `evil-snipe-scope'."
  :group 'evil-snipe
  :type 'symbol)

(defcustom evil-snipe-spillover-scope nil
  "If non-nil, snipe will expand the search scope to this when a snipe fails,
and continue the search (until it finds something or even this scope fails).

Accepts the same values as `evil-snipe-scope' and `evil-snipe-repeat-scope'.
Is only useful if set to the same or broader scope than either."
  :group 'evil-snipe
  :type 'symbol)

(defcustom evil-snipe-repeat-keys t
  "If non-nil, pressing s/S after a search will repeat it. If
`evil-snipe-override-evil' is non-nil, this applies to f/F/t/T as well."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-show-prompt t
  "If non-nil, show 'N>' prompt while sniping."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-smart-case nil
  "By default, searches are case sensitive. If `evil-snipe-smart-case' is
enabled, searches are case sensitive only if search contains capital
letters."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-auto-scroll nil
  "If non-nil, the window will scroll to follow the cursor."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-aliases '()
  "A list of characters mapped to regexps '(CHAR REGEX). If CHAR is used in a snipe, it
will be replaced with REGEX. These aliases apply globally. To set an alias for a specific
mode use:

    (add-hook 'c++-mode-hook
      (lambda ()
        (make-variable-buffer-local 'evil-snipe-aliases)
        (push '(?\[ \"[[{(]\") evil-snipe-aliases)))"
  :group 'evil-snipe
  :type '(repeat (cons (character :tag "Key")
                       (regexp :tag "Pattern"))))
(define-obsolete-variable-alias 'evil-snipe-symbol-groups 'evil-snipe-aliases "v2.0.0")

(defvar evil-snipe-auto-disable-substitute t
  "Disables evil's native s/S functionality (substitute) if non-nil. By default
this is t, since they are mostly redundant with other motions. s can be done
via cl and S with cc (or C).

MUST BE SET BEFORE EVIL-SNIPE IS LOADED.")

(defvar evil-snipe-use-vim-sneak-bindings nil
  "Uses only Z and z under operator state, as vim-sneak does. This frees the
x binding in operator state, if user wishes to use cx for evil-exchange or
anything else.

MUST BE SET BEFORE EVIL-SNIPE IS LOADED.")

(defcustom evil-snipe-skip-leading-whitespace t
  "If non-nil, single char sniping (f/F/t/T) will skip over leading whitespaces
in a line (when you snipe for whitespace, e.g. f<space> or f<tab>)."
  :group 'evil-snipe
  :type 'boolean)

(defcustom evil-snipe-tab-increment nil
  "If non-nil, pressing TAB while sniping will add another character to your
current search. For example, typing sab will search for 'ab'. In order to search
for 'abcd', you do sa<tab><tab>bcd.

If nil, TAB will search for literal tab characters."
  :group 'evil-snipe
  :type 'boolean)

(defface evil-snipe-first-match-face
  '((t (:inherit isearch)))
  "Face for first match when sniping"
  :group 'evil-snipe)

(defface evil-snipe-matches-face
  '((t (:inherit region)))
  "Face for other matches when sniping"
  :group 'evil-snipe)

;; State vars
(defvar evil-snipe--last nil)

(defvar evil-snipe--last-repeat nil)

(defvar evil-snipe--last-direction t
  "Direction of the last search.")

(defvar evil-snipe--consume-match t
  "Whether the search should be inclusive of the match or not.")

(defvar evil-snipe--match-count 2
  "Number of characters to match. Can be let-bound to create motions that search
  for N characters. Do not set directly, unless you want to change the default
  number of characters to search.")

(defvar evil-snipe--transient-map-func nil)


(defun evil-snipe--case-p (keys)
  (and evil-snipe-smart-case
       (let ((case-fold-search nil))
         (not (string-match-p "[A-Z]" (mapconcat 'char-to-string keys ""))))))

(defun evil-snipe--process-key (key)
  (let ((regex-p (assoc key evil-snipe-aliases))
        (keystr (char-to-string key)))
    (cons keystr
          (if regex-p (elt regex-p 1) (regexp-quote keystr)))))

(defun evil-snipe--collect-keys (&optional count forward-p)
  "The core of evil-snipe's N-character searching. Prompts for `evil-snipe--match-count'
characters, which can be incremented by pressing TAB. Backspace works for correcting
yourself too."
  (let ((echo-keystrokes 0) ; don't mess with the prompt, Emacs
        (count (or count 1))
        (i evil-snipe--match-count)
        keys)
    (unless forward-p
      (setq count (- count)))
    (unwind-protect
        (catch 'abort
          (while (> i 0)
            (let ((key (read-event
                        (and evil-snipe-show-prompt
                             (format "%d>%s" i (mapconcat 'char-to-string keys ""))))))
              (cond
               ;; Tab = adds more characters if `evil-snipe-tab-increment'
               ((and evil-snipe-tab-increment (eq key 'tab))
                (setq i (1+ i)))
               ;; Enter = do search with current chars
               ((eq key 'return)
                (throw 'abort (if (= i evil-snipe--match-count) 'repeat keys)))
               ;; Abort
               ((eq key 'escape)
                (evil-snipe--cleanup)
                (throw 'abort 'abort))
               (t ; Otherwise, process key
                (cond ((eq key 'backspace)  ; if backspace, delete a character
                       (cl-incf i)
                       (if (<= (length keys) 1)
                           (progn (evil-snipe--cleanup)
                                  (throw 'abort 'abort))
                         (nbutlast keys)))
                      (t ;; Otherwise add it
                       (when (eq key 'tab) (setq key ?\t)) ; literal tabs
                       (setq keys (push key keys))
                       (cl-decf i)))
                (when evil-snipe-enable-incremental-highlight
                  (evil-snipe--cleanup)
                  (evil-snipe--highlight-all count keys)
                  (add-hook 'pre-command-hook 'evil-snipe--cleanup))))))
          (reverse keys)))))

(defun evil-snipe--bounds (&optional forward-p count)
  "Returns a cons cell containing (beg . end), which represents the search scope
depending on what `evil-snipe-scope' is set to."
  (let* ((point+1 (1+ (point)))
         (evil-snipe-scope (or (if (and count (> (abs count) 1)) evil-snipe-spillover-scope) evil-snipe-scope))
         (bounds (cl-case evil-snipe-scope
                   ('line
                    (if forward-p
                        `(,point+1 . ,(line-end-position))
                      `(,(line-beginning-position) . ,(point))))
                   ('visible
                    (if forward-p
                        `(,point+1 . ,(1- (window-end)))
                      `(,(window-start) . ,(point))))
                   ('buffer
                    (if forward-p
                        `(,point+1 . ,(point-max))
                      `(,(point-min) . ,(point))))
                   ('whole-line
                    `(,(line-beginning-position) . ,(line-end-position)))
                   ('whole-visible
                    `(,(window-start) . ,(1- (window-end))))
                   ('whole-buffer
                    `(,(point-min) . ,(point-max)))
                   (t
                    (error "Invalid scope: %s" evil-snipe-scope))))
         (end (cdr bounds)))
    (when (> (car bounds) end)
      (setq bounds `(,end . ,end)))
    bounds))

(defun evil-snipe--highlight (beg end &optional first-p)
  "Highlights region between beg and end. If first-p is t, then use
`evil-snipe-first-p-match-face'"
  (when (and first-p (overlays-in beg end))
    (remove-overlays beg end 'category 'evil-snipe))
  (let ((overlay (make-overlay beg end nil nil nil)))
    (overlay-put overlay 'category 'evil-snipe)
    (overlay-put overlay 'face (if first-p
                                   'evil-snipe-first-match-face
                                 'evil-snipe-matches-face))
    overlay))

(defun evil-snipe--highlight-all (count keys)
  "Highlight all instances of `keys' ahead of the cursor, or behind it if
`forward-p' is nil."
  (let* ((case-fold-search (evil-snipe--case-p keys))
         (match (mapconcat 'char-to-string keys ""))
         (forward-p (> count 0))
         (bounds (evil-snipe--bounds forward-p))
         (orig-pt (point))
         (i 0)
         overlays)
    (save-excursion
      (goto-char (car bounds))
      (while (search-forward match (cdr bounds) t 1)
        (let ((hl-beg (match-beginning 0))
              (hl-end (match-end 0)))
          (if (and evil-snipe-skip-leading-whitespace
                   (looking-at-p "[ \t][ \t]+"))
              (progn
                (re-search-forward-lax-whitespace " ")
                (backward-char (- hl-end hl-beg)))
            (push (evil-snipe--highlight hl-beg hl-end) overlays)))))
    overlays))

(defun evil-snipe--cleanup ()
  "Disables overlays and cleans up after evil-snipe."
  (when evil-snipe-local-mode
    (remove-overlays nil nil 'category 'evil-snipe))
  (remove-hook 'pre-command-hook 'evil-snipe--cleanup))

(defun evil-snipe--disable-transient-map ()
  "Disable lingering transient map, if necessary."
  (when (and evil-snipe-local-mode (functionp evil-snipe--transient-map-func))
    (funcall evil-snipe--transient-map-func)
    (setq evil-snipe--transient-map-func nil)))

(defun evil-snipe--transient-map (forward-key backward-key)
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map evil-snipe-parent-transient-map)
    (when evil-snipe-repeat-keys
      (define-key map forward-key 'evil-snipe-repeat)
      (define-key map backward-key 'evil-snipe-repeat-reverse))
    map))


(defun evil-snipe-seek (count keys &optional keymap)
  "Perform a snipe. KEYS is a list of characters provided by <-c> and <+c>
interactive codes. KEYMAP is the transient map to activate afterwards."
  (let ((case-fold-search (evil-snipe--case-p keys)))
    (cl-case keys
      ('abort (setq evil-inhibit-operator t))
      ;; if <enter>, repeat last search
      ('repeat (if evil-snipe--last-direction
                   (evil-snipe-repeat count)
                 (evil-snipe-repeat-reverse count)))
      ;; If KEYS is empty
      ('() (user-error "No keys provided!"))
      ;; Otherwise, perform the search
      (t (let ((count (or count (if evil-snipe--last-direction 1 -1)))
               (keymap (if (keymapp keymap) keymap))
               (data (mapcar 'evil-snipe--process-key keys)))
           (unless evil-snipe--last-repeat
             (setq evil-snipe--last (list count keys keymap
                                          evil-snipe--consume-match
                                          evil-snipe--match-count)))
           (evil-snipe--seek count data)
           (point))))))

(defun evil-snipe--seek (count data)
  "(INTERNAL) Perform a snipe and adjust cursor position depending on mode."
  (evil-snipe--cleanup)
  (let ((orig-point (point))
        (forward-p (> count 0))
        (string (mapconcat 'cdr data "")))
    ;; Skip over leading whitespace
    (when (and evil-snipe-skip-leading-whitespace
               (string-match-p "^[ \t]+$" string))
      (let ((at-indent (- (save-excursion (back-to-indentation) (point))
                          (length string))))
        (when (funcall (if forward-p '< '<=) orig-point at-indent)
          (if forward-p
              (goto-char (max 1 (1- at-indent)))
            (evil-beginning-of-line)))))
    ;; Adjust search starting point
    (if forward-p (forward-char))
    (unless evil-snipe--consume-match
      (forward-char (if forward-p 1 -1)))
    (let ((scope (evil-snipe--bounds forward-p count))
          (evil-op-p (evil-operator-state-p))
          (evil-vs-p (evil-visual-state-p))
          new-orig-point)
      (unwind-protect
          (if (re-search-forward string (if forward-p (cdr scope) (car scope)) t count) ;; hi |
              (let* ((beg (match-beginning 0))
                     (end (match-end 0))
                     (len (- end beg)))
                ;; Adjust cursor end position
                (if forward-p
                    (progn
                      (goto-char (if evil-vs-p
                                     (if evil-snipe--consume-match end beg)
                                   (if evil-op-p end beg)))
                      (if evil-snipe--consume-match
                          (when evil-vs-p
                            (backward-char))
                        (backward-char len)
                        (when (and (> len 1) (not evil-op-p))
                          (forward-char))))
                  (goto-char (if evil-snipe--consume-match beg end)))
                ;; Follow the cursor
                (when evil-snipe-auto-scroll
                  (setq new-orig-point (point))
                  (if (or (> (window-start) new-orig-point)
                          (< (window-end) new-orig-point))
                      (evil-scroll-line-to-center (line-number-at-pos))
                    (evil-scroll-line-down (- (line-number-at-pos)
                                              (line-number-at-pos orig-point))))
                  (goto-char new-orig-point))
                ;; Skip over leading whitespace after the search
                (when (and evil-snipe-skip-leading-whitespace
                           forward-p
                           (looking-at-p "[ \t][ \t]+"))
                  (re-search-forward-lax-whitespace " ")
                  (backward-char len))
                (unless evil-op-p
                  (unless evil-vs-p
                    ;; Highlight first result (but not in operator/visual mode)
                    (when evil-snipe-enable-highlight
                      (evil-snipe--highlight beg end t)))
                  ;; Activate the repeat keymap
                  (when (and keymap)
                    (setq evil-snipe--transient-map-func (set-transient-map keymap)))))
            ;; Try to "spill over" into new scope on failed search
            (if evil-snipe-spillover-scope
                (let ((evil-snipe-scope evil-snipe-spillover-scope)
                      evil-snipe-spillover-scope)
                  (evil-snipe--seek count data))
              ;; If, at last, it fails...
              (goto-char orig-point)
              (user-error "Can't find %s" ;; show invisible keys
                (replace-regexp-in-string "\t" "<TAB>"
                (replace-regexp-in-string "\s" "<SPC>" (mapconcat 'car data ""))))))
        (when evil-snipe-enable-highlight
          (evil-snipe--highlight-all count string))
        (add-hook 'pre-command-hook 'evil-snipe--cleanup)))
    (point)))

(evil-define-motion evil-snipe-repeat (count)
  "Repeat the last evil-snipe `count' times"
  (interactive "<c>")
  (unless (listp evil-snipe--last)
    (user-error "Nothing to repeat"))
  (let ((last-count (nth 0 evil-snipe--last))
        (last-keys (nth 1 evil-snipe--last))
        (last-keymap (nth 2 evil-snipe--last))
        (last-consume-match (nth 3 evil-snipe--last))
        (last-match-count (nth 4 evil-snipe--last))
        (evil-snipe--last-repeat t)
        (evil-snipe-scope (or evil-snipe-repeat-scope evil-snipe-scope)))
    (let ((evil-snipe--consume-match last-consume-match)
          (evil-snipe--match-count last-match-count))
      (evil-snipe-seek (* (or count 1) last-count) last-keys last-keymap))))

(evil-define-motion evil-snipe-repeat-reverse (count)
  "Repeat the inverse of the last evil-snipe `count' times"
  (interactive "<c>")
  (evil-snipe-repeat (or (and count (- count)) -1)))


(defmacro evil-snipe-def (n type forward-key backward-key)
  (let ((forward-fn (intern (format "evil-snipe-%s" forward-key)))
        (backward-fn (intern (format "evil-snipe-%s" backward-key))))
    `(progn
       (evil-define-motion ,forward-fn (count keys)
         ,(concat "Jumps to the next " (int-to-string n)
                  "-char match COUNT matches away. Including KEYS is a list of character codes.")
         :jump t
         (interactive
          (let ((count (when current-prefix-arg (prefix-numeric-value current-prefix-arg))))
            (list (progn (setq evil-snipe--last-direction t) count)
                  (let ((evil-snipe--match-count ,n))
                    (evil-snipe--collect-keys count evil-snipe--last-direction)))))
         (let ((evil-snipe--consume-match ,(eq type 'inclusive)))
           (evil-snipe-seek
            count keys (evil-snipe--transient-map ,forward-key ,backward-key))))

       (evil-define-motion ,backward-fn (count keys)
         ,(concat "Performs an backwards `" (symbol-name forward-fn) "'.")
         :jump t
         (interactive
          (let ((count (when current-prefix-arg (prefix-numeric-value current-prefix-arg))))
            (list (progn (setq evil-snipe--last-direction nil) count)
                  (let ((evil-snipe--match-count ,n))
                    (evil-snipe--collect-keys count evil-snipe--last-direction)))))
         (let ((evil-snipe--consume-match ,(eq type 'inclusive)))
           (evil-snipe-seek
            (or (and count (- count)) -1) keys
            (evil-snipe--transient-map ,forward-key ,backward-key)))))))

;;;###autoload (autoload 'evil-snipe-s "evil-snipe" nil t)
;;;###autoload (autoload 'evil-snipe-S "evil-snipe" nil t)
(evil-snipe-def 2 inclusive "s" "S")

;;;###autoload (autoload 'evil-snipe-x "evil-snipe" nil t)
;;;###autoload (autoload 'evil-snipe-X "evil-snipe" nil t)
(evil-snipe-def 2 exclusive "x" "X")

;;;###autoload (autoload 'evil-snipe-f "evil-snipe" nil t)
;;;###autoload (autoload 'evil-snipe-F "evil-snipe" nil t)
(evil-snipe-def 1 inclusive "f" "F")

;;;###autoload (autoload 'evil-snipe-t "evil-snipe" nil t)
;;;###autoload (autoload 'evil-snipe-T "evil-snipe" nil t)
(evil-snipe-def 1 exclusive "t" "T")


(defvar evil-snipe-mode-map
  (let ((map (make-sparse-keymap)))
    (evil-define-key 'motion map "s" 'evil-snipe-s)
    (evil-define-key 'motion map "S" 'evil-snipe-S)

    ;; Bind in operator state
    (if evil-snipe-use-vim-sneak-bindings
        (progn
          (evil-define-key 'operator map "z" 'evil-snipe-x)
          (evil-define-key 'operator map "Z" 'evil-snipe-X))
      (progn
        (evil-define-key 'operator map "z" 'evil-snipe-s)
        (evil-define-key 'operator map "Z" 'evil-snipe-S)
        (evil-define-key 'operator map "x" 'evil-snipe-x)
        (evil-define-key 'operator map "X" 'evil-snipe-X)))

    ;; Disable s/S (substitute)
    (when evil-snipe-auto-disable-substitute
      (define-key evil-normal-state-map "s" nil)
      (define-key evil-normal-state-map "S" nil))
    map))

(defvar evil-snipe-override-mode-map
  (let ((map (make-sparse-keymap)))
    (evil-define-key 'motion map "f" 'evil-snipe-f)
    (evil-define-key 'motion map "F" 'evil-snipe-F)
    (evil-define-key 'motion map "t" 'evil-snipe-t)
    (evil-define-key 'motion map "T" 'evil-snipe-T)

    (when evil-snipe-override-evil-repeat-keys
      (evil-define-key 'motion map ";" 'evil-snipe-repeat)
      (evil-define-key 'motion map "," 'evil-snipe-repeat-reverse))
    map))

(defvar evil-snipe-parent-transient-map
  (let ((map (make-sparse-keymap)))
    ;; So ; and , are common to all sub keymaps
    (define-key map ";" 'evil-snipe-repeat)
    (define-key map "," 'evil-snipe-repeat-reverse)
    map))

(unless (fboundp 'set-transient-map)
  (defalias 'set-transient-map 'set-temporary-overlay-map))

;;;###autoload
(define-globalized-minor-mode evil-snipe-mode
  evil-snipe-local-mode turn-on-evil-snipe-mode)

;;;###autoload
(define-globalized-minor-mode evil-snipe-override-mode
  evil-snipe-override-local-mode turn-on-evil-snipe-override-mode)

;;;###autoload
(define-minor-mode evil-snipe-local-mode
  "evil-snipe minor mode."
  :lighter " snipe"
  :keymap evil-snipe-mode-map
  :group 'evil-snipe
  (if evil-snipe-local-mode
      (progn
        (when (fboundp 'advice-add)
          (advice-add 'evil-force-normal-state :before 'evil-snipe--cleanup))
        (add-hook 'evil-insert-state-entry-hook 'evil-snipe--disable-transient-map nil t))
    (when (fboundp 'advice-remove)
      (advice-remove 'evil-force-normal-state 'evil-snipe--cleanup))
    (remove-hook 'evil-insert-state-entry-hook 'evil-snipe--disable-transient-map t)))

;;;###autoload
(define-minor-mode evil-snipe-override-local-mode
  "evil-snipe minor mode that overrides evil-mode f/F/t/T/;/, bindings."
  :keymap evil-snipe-override-mode-map
  :group 'evil-snipe
  (if evil-snipe-override-local-mode
      (unless evil-snipe-local-mode
        (evil-snipe-local-mode 1))
    (evil-snipe-local-mode -1)))

;;;###autoload
(defun turn-on-evil-snipe-mode ()
  "Enable evil-snipe-mode in the current buffer."
  (evil-snipe-local-mode 1))

;;;###autoload
(defun turn-on-evil-snipe-override-mode ()
  "Enable evil-snipe-mode in the current buffer."
  (evil-snipe-override-local-mode 1))

;;;###autoload
(defun turn-off-evil-snipe-mode ()
  "Disable evil-snipe-mode in the current buffer."
  (evil-snipe-local-mode -1))

;;;###autoload
(defun turn-off-evil-snipe-override-mode ()
  "Disable evil-snipe-override-mode in the current buffer."
  (evil-snipe-override-local-mode -1))

(provide 'evil-snipe)
;;; evil-snipe.el ends here
