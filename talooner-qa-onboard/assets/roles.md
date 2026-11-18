# Roles: Who May Do What

> Which role may view, create, edit and delete the main records of each area.
> Written from <the role definitions and policies>. Talooner QA reads this page
> to decide which roles a scenario runs as and which should be denied.

## How Roles Work

Every user holds one role per area. <How roles are stored, what an account
admin may do on top, and what a role with no access sees.>

## Orders

Roles, lowest to highest: `viewer`, `clerk`, `manager`.

| Record (page) | View | Create | Edit | Delete |
|---|---|---|---|---|
| Orders (`orders`, `order`, `new_order`, `edit_order`) | all three roles | `clerk`, `manager` | `clerk` own orders; `manager` all | `manager` |
| Refunds (`order`, the Refund button) | — | `manager` | — | — |

A guest is sent to `new_user_session` on every page above.
