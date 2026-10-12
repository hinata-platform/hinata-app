# hinata_device_lock

Answers whether the device is locked (`KeyguardManager.isKeyguardLocked`) on
Android. A plugin rather than a channel in `MainActivity`, because a plugin is
registered in every Flutter engine, including the background engines that run
a timer action from a notification, a widget or the Quick Settings tile
(HIN-103). Every other platform answers `false`.
