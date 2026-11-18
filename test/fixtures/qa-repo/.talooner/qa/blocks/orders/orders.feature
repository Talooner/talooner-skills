@page:orders @data:order
Block: open the order list
  Then I see "Order number"

@page:order @data:order
Block: open an order
  Then I see "Delivery address"

@page:new_order
Block: start creating an order
  Then I see "Create a new order"

@page:order @data:order:paid
Block: refund a paid order
  When I click "Refund"
  And I confirm the dialog
  Then I see "Refunded"
