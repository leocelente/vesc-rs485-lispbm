(define rpm 100)
(defun get-rpm () rpm)
(defun set-rpm (new-rpm) (setvar 'rpm new-rpm ))

(define duty 0.05)
(defun get-duty () duty)
(defun set-duty (new-duty) (setvar 'duty new-duty ))

(define uart-write 'print)
(define pin-rs485re 1)
(define pin-rs485de 2)
(define pin-mode-output 1)

(defun gpio-configure (pin mode) t)
(defun gpio-write (pin state) t)
(defun uart-start (baud) t)

(defun abs (x) (max x (* -1 x)))